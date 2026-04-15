#!/usr/bin/env bash
# create-gha-kubeconfig.sh
#
# Creates a scoped ServiceAccount + RBAC for GitHub Actions and outputs a
# base64-encoded kubeconfig ready to paste into a GitHub Actions secret.
#
# Usage:
#   ./scripts/create-gha-kubeconfig.sh <namespace>
#
# Example:
#   ./scripts/create-gha-kubeconfig.sh pico
#   ./scripts/create-gha-kubeconfig.sh math
#
# RBAC scope (namespace-only, no cluster-wide access):
#   - deployments: get/list/patch/update  (for kubectl set image, rollout status)
#   - pods:        get/list               (for kubectl rollout status, debugging)
#   - ingresses:   get/list/patch/update  (for annotation updates if needed)
#   - services, configmaps: get/list      (read-only, for inspection)
#
#   Note: no 'create' on deployments by design — GHA should update existing
#   workloads, not bootstrap new ones. Run 'make apply-*' locally for that.
#
# Token lifetime: 8760h (1 year). Re-run this script annually to rotate.
#
# Connectivity: the kubeconfig server URL is taken from your current kubectl
# context. If that's a Tailscale IP (100.x.x.x), GitHub-hosted runners cannot
# reach it. Options:
#   - Self-hosted runner on the homelab (simplest)
#   - Tailscale GitHub Action to join the runner to your tailnet
#     https://tailscale.com/kb/1276/github-actions

set -euo pipefail

NAMESPACE=${1:?Usage: $0 <namespace>}
SA_NAME="github-actions"

echo "==> Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying ServiceAccount, Role, RoleBinding..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SA_NAME
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $SA_NAME
  namespace: $NAMESPACE
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "patch", "update"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "patch", "update"]
- apiGroups: [""]
  resources: ["services", "configmaps"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $SA_NAME
  namespace: $NAMESPACE
subjects:
- kind: ServiceAccount
  name: $SA_NAME
  namespace: $NAMESPACE
roleRef:
  kind: Role
  name: $SA_NAME
  apiGroup: rbac.authorization.k8s.io
EOF

echo "==> Generating token (expires in 1 year)..."
TOKEN=$(kubectl create token "$SA_NAME" -n "$NAMESPACE" --duration=8760h)

echo "==> Reading cluster info from current context..."
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

KUBECONFIG_CONTENT=$(cat <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CA
    server: $SERVER
  name: home
contexts:
- context:
    cluster: home
    namespace: $NAMESPACE
    user: $SA_NAME
  name: home
current-context: home
users:
- name: $SA_NAME
  user:
    token: $TOKEN
EOF
)

# base64 flags differ between macOS and Linux
if base64 --version 2>&1 | grep -q GNU; then
  B64=$(echo "$KUBECONFIG_CONTENT" | base64 -w 0)
else
  B64=$(echo "$KUBECONFIG_CONTENT" | base64)
fi

echo ""
echo "=== KUBECONFIG (base64 encoded) ==="
echo "Add this as a GitHub Actions secret named KUBECONFIG_${NAMESPACE^^}:"
echo ""
echo "$B64"
echo ""
echo "Server: $SERVER"
echo "Namespace: $NAMESPACE"
echo "ServiceAccount: $SA_NAME"
