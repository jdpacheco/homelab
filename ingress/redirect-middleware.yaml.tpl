apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-to-www
  namespace: default
spec:
  redirectRegex:
    regex: "^https?://[^/]+(.*)"
    replacement: "https://${REDIRECT_DEST}.${DOMAIN}$1"
    permanent: false