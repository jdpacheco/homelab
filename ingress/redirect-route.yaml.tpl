apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: catch-all
  namespace: default
spec:
  entryPoints:
    - web
    - websecure
  routes:
  - match: HostRegexp(`^.+\.${DOMAIN}$`)
    kind: Rule
    priority: 1
    middlewares:
    - name: redirect-to-www
    services:
    - name: noop@internal
      kind: TraefikService