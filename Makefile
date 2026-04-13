include .env
export

.PHONY: apply-cert-manager apply-monitoring apply-hello apply-redirect apply-all dry-run diff \
        helm-add-repos helm-cert-manager helm-monitoring helm-reflector helm-all

# Helm
helm-add-repos:
	helm repo add jetstack https://charts.jetstack.io
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add emberstack https://emberstack.github.io/helm-charts
	helm repo update

helm-cert-manager:
	helm upgrade --install cert-manager jetstack/cert-manager \
		--namespace cert-manager --create-namespace \
		--set crds.enabled=true

helm-monitoring:
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
		--namespace monitoring --create-namespace

helm-reflector:
	helm upgrade --install reflector emberstack/reflector \
		--namespace kube-system

# Run helm-add-repos first if this is a fresh machine
helm-all: helm-cert-manager helm-monitoring helm-reflector

# Manifests
apply-cert-manager:
	envsubst < cert-manager/clusterissuer-stage.yaml.tpl | kubectl apply -f -
	envsubst < cert-manager/clusterissuer-prod.yaml.tpl  | kubectl apply -f -
	envsubst < cert-manager/prod-cert.yaml.tpl           | kubectl apply -f -

apply-monitoring:
	envsubst < monitoring/grafana-ingress.yaml.tpl | kubectl apply -f -

apply-hello:
	kubectl apply -f app/hello/deployment.yaml
	kubectl apply -f app/hello/service.yaml
	envsubst < app/hello/ingress.yaml.tpl | kubectl apply -f -

apply-redirect:
	envsubst < ingress/redirect-middleware.yaml.tpl | kubectl apply -f -
	envsubst < ingress/redirect-route.yaml.tpl | kubectl apply -f -

apply-all: apply-cert-manager apply-monitoring apply-hello apply-redirect

dry-run:
	@echo "=== cert-manager/clusterissuer-stage ===" && envsubst < cert-manager/clusterissuer-stage.yaml.tpl
	@echo "=== cert-manager/clusterissuer-prod ===" && envsubst < cert-manager/clusterissuer-prod.yaml.tpl
	@echo "=== cert-manager/prod-cert ===" && envsubst < cert-manager/prod-cert.yaml.tpl
	@echo "=== monitoring/grafana-ingress ===" && envsubst < monitoring/grafana-ingress.yaml.tpl
	@echo "=== app/hello/ingress ===" && envsubst < app/hello/ingress.yaml.tpl
	@echo "=== ingress/redirect-middleware ===" && envsubst < ingress/redirect-middleware.yaml.tpl
	@echo "=== ingress/redirect-route ===" && envsubst < ingress/redirect-route.yaml.tpl

diff:
	-@envsubst < cert-manager/clusterissuer-stage.yaml.tpl | kubectl diff -f -
	-@envsubst < cert-manager/clusterissuer-prod.yaml.tpl  | kubectl diff -f -
	-@envsubst < cert-manager/prod-cert.yaml.tpl           | kubectl diff -f -
	-@envsubst < monitoring/grafana-ingress.yaml.tpl       | kubectl diff -f -
	-@envsubst < app/hello/ingress.yaml.tpl                | kubectl diff -f -
	-@envsubst < ingress/redirect-middleware.yaml.tpl      | kubectl diff -f -
	-@envsubst < ingress/redirect-route.yaml.tpl           | kubectl diff -f -
