include .env
export

.PHONY: apply-cert-manager apply-monitoring apply-hello apply-redirect apply-all dry-run diff

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
