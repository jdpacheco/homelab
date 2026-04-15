# homelab

Personal k3s homelab infrastructure powering [jamespacheco.dev](https://jamespacheco.dev).

## Architecture
```
Browser → Cloudflare (TLS, DDoS) → Cloudflare Tunnel → Traefik → Services
                                                         ↑
                                              Tailscale (private kubectl access)
```

All public traffic enters via Cloudflare Tunnel — no inbound ports are open on the
host router. Private cluster access (kubectl, registry) goes through Tailscale.

## Stack

| Component | Tool | Notes |
|-----------|------|-------|
| Kubernetes | k3s | Single node, bare metal Arch Linux |
| Ingress | Traefik | Bundled with k3s |
| Load Balancer | Klipper | Bundled with k3s, sufficient for single node |
| Public traffic | Cloudflare Tunnel | No open inbound ports |
| TLS | cert-manager + Let's Encrypt | DNS-01 challenge via Cloudflare API |
| Certificates | Wildcard `*.jamespacheco.dev` | Single cert covers all subdomains |
| Observability | kube-prometheus-stack | Prometheus + Grafana + node-exporter |
| Secret mirroring | reflector | Auto-mirrors TLS secrets across namespaces |
| Private access | Tailscale | kubectl, registry, SSH |
| DNS | Cloudflare | DDNS, wildcard CNAME, proxied |

## Prerequisites

- `kubectl` configured against the cluster
- `helm` installed
- `envsubst` available (`gettext` package)
- `.env` populated from `.env.example`
- Helm repos added — run `make helm-add-repos` once on a fresh machine before `make helm-all`

## Usage

```bash
make dry-run      # preview all rendered templates
make diff         # show what would change in the cluster
make apply-all    # apply all manifests

# Or apply individual components:
make apply-cert-manager
make apply-monitoring
make apply-hello
make apply-redirect
```

## Services

| Subdomain | Description |
|-----------|-------------|
| jamespacheco.dev | Landing page |
| grafana.jamespacheco.dev | Cluster observability |
| hello.jamespacheco.dev | Smoke test / ingress validation |

## Repository Structure
```
homelab/
├── cert-manager/     # ClusterIssuers and Certificate resources
├── monitoring/       # Grafana ingress
├── ingress/          # Catch-all redirect middleware and IngressRoute
├── app/
│   └── hello/        # Smoke test deployment (nginx)
├── scripts/
│   └── create-gha-kubeconfig.sh  # Scoped kubeconfig for GitHub Actions
├── .env.example      # Required environment variables
└── Makefile          # Template rendering and apply targets
```

## Connecting an App to the Platform

Apps live in their own repos and manage their own k8s manifests. This repo
provides the platform they run on. When onboarding a new app:

### What the platform provides automatically

- **TLS** — the wildcard `*.jamespacheco.dev` cert covers any subdomain.
  reflector mirrors it to the app's namespace; no cert request needed.
- **Ingress** — Traefik is already running. Point an Ingress at it and traffic flows.
- **Catch-all redirect** — any unmatched subdomain redirects to the landing page.

### Set up GitHub Actions access

Generate a scoped kubeconfig for the app's namespace:

```bash
./scripts/create-gha-kubeconfig.sh <namespace>
```

This creates a `github-actions` ServiceAccount with namespace-scoped RBAC
(deployments patch/update, pods read, ingresses patch/update, services/configmaps
read), generates a 1-year token, and prints a base64-encoded kubeconfig.

Add the output as a GitHub Actions secret named `KUBECONFIG_<NAMESPACE>` (the
script prints the exact name).

**Connectivity:** the kubeconfig server URL is the cluster's Tailscale IP. GitHub
hosted runners cannot reach it by default. Use either:
- A self-hosted runner on the homelab, or
- The [Tailscale GitHub Action](https://tailscale.com/kb/1276/github-actions) to
  join the runner to your tailnet before deploying.

**Token rotation:** tokens expire after 1 year. Re-run the script to rotate.

## Design Decisions

### Cloudflare Tunnel over port forwarding
Rather than opening inbound ports on the home router, all public traffic routes
through a Cloudflare Tunnel (`cloudflared` running as a systemd service). This
keeps the home IP out of public DNS entirely, provides DDoS mitigation at
Cloudflare's edge, and means the attack surface on the host is effectively zero
for public traffic.

### Tailscale for private access
kubectl, SSH, and eventually the container registry are accessed over Tailscale
rather than exposed publicly. Tailscale provides stable addresses for cluster
nodes regardless of LAN DHCP changes, and allows the k3s API server TLS cert
to be scoped to the Tailscale IP rather than a public address.

### DNS-01 over HTTP-01 for cert-manager
Let's Encrypt's HTTP-01 challenge requires the domain to be publicly reachable
on port 80. DNS-01 proves domain ownership via a DNS TXT record instead, which
works for any domain including those behind Cloudflare Tunnel. cert-manager
creates and removes the TXT record automatically via the Cloudflare API.

### Wildcard certificate
A single `*.jamespacheco.dev` certificate covers all subdomains. New services
get HTTPS automatically without requesting new certificates. Wildcard certs
require DNS-01 challenge, which is already configured.

### Klipper over MetalLB
k3s ships with Klipper as a lightweight LoadBalancer implementation. For a
single-node cluster with one ingress controller (Traefik), Klipper is
sufficient — only one LoadBalancer service exists. MetalLB would be appropriate
for multi-node or multiple LoadBalancer services.

### Traefik entrypoints annotation
Traefik ingress resources should **not** use the
`traefik.ingress.kubernetes.io/router.entrypoints: websecure` annotation when
behind Cloudflare Tunnel. The tunnel delivers HTTP to the host even though the
public-facing connection is HTTPS — annotating for `websecure` only causes
Traefik to ignore requests arriving on the `web` entrypoint. Omit the
annotation and let Traefik default to all entrypoints.

### Cross-namespace TLS secrets
Kubernetes secrets are namespace-scoped. The wildcard TLS certificate lives in
the `default` namespace but ingress resources in other namespaces (e.g.
`monitoring`) need access to it. [reflector](https://github.com/emberstack/kubernetes-reflector)
automatically mirrors the secret to any namespace that needs it. The Certificate
resource is annotated to allow reflection, and reflector handles the rest.

### Catch-all redirect
An IngressRoute with `priority: 1` catches any subdomain not matched by a
specific ingress and redirects to the landing page. Uses `redirectRegex`
middleware to preserve the request path. `permanent: false` (307) allows the
redirect destination to change without browser cache issues.

### envsubst for templating
Manifests are stored as `.yaml.tpl` files with `${VARIABLE}` placeholders.
`envsubst` renders them with values from `.env` at apply time. This keeps
sensitive or environment-specific values (domain, email) out of the repository
while keeping the templates readable. The Makefile exports `.env` variables
into its own subshell — nothing leaks to the host shell environment.

## Known Issues / Future Work

- Single node means no real fault tolerance — node failure takes everything down
- Container registry not yet deployed — currently using public images only
- GHA pipeline not yet configured — deployments are manual via `make apply-*`