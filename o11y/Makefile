SHELL := bash

.DEFAULT_GOAL := help
.PHONY: help create apply bootstrap list destroy

help: ## show available targets
	@awk 'BEGIN{FS=":.*?## "} /^[a-zA-Z_-]+:.*?## /{printf "  %-12s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

create: apply bootstrap ## create containers and start monitoring stack

apply: ## terraform init + apply (generates metrics cert and containers)
	terraform init -input=false -upgrade=false
	terraform apply -auto-approve

bootstrap: ## install prometheus + grafana and push configs via incus exec
	@# --- prometheus ---
	@echo "=== prometheus ==="
	incus exec cluster:prometheus -- apk add --no-cache prometheus
	incus file push prometheus.yml  cluster:prometheus/etc/prometheus/prometheus.yml
	incus file push metrics.crt     cluster:prometheus/etc/prometheus/metrics.crt
	incus file push metrics.key     cluster:prometheus/etc/prometheus/metrics.key
	incus exec cluster:prometheus -- chown -R prometheus:prometheus /etc/prometheus/
	incus exec cluster:prometheus -- rc-update add prometheus default
	incus exec cluster:prometheus -- rc-service prometheus start
	@# --- grafana ---
	@echo "=== grafana ==="
	incus exec cluster:grafana -- apk add --no-cache grafana
	@# Alpine's grafana OpenRC script binds to 127.0.0.1 by default; open to all interfaces.
	incus exec cluster:grafana -- sed -i \
	  's/cfg:server.http_addr=127.0.0.1/cfg:server.http_addr=0.0.0.0/' \
	  /etc/conf.d/grafana
	@# Alpine grafana uses /var/lib/grafana/provisioning (not /etc/grafana/provisioning).
	incus exec cluster:grafana -- mkdir -p \
	  /var/lib/grafana/provisioning/datasources \
	  /var/lib/grafana/provisioning/dashboards \
	  /var/lib/grafana/dashboards
	incus file push grafana/datasource.yml \
	  cluster:grafana/var/lib/grafana/provisioning/datasources/prometheus.yml
	incus file push grafana/dashboard-provider.yml \
	  cluster:grafana/var/lib/grafana/provisioning/dashboards/provider.yml
	curl -sL "https://grafana.com/api/dashboards/19727/revisions/latest/download" \
	  | sed 's/\$${DS_INCUS}/incus-prometheus/g' \
	  > /tmp/incus-dashboard.json
	incus file push /tmp/incus-dashboard.json \
	  cluster:grafana/var/lib/grafana/dashboards/incus.json
	curl -sL "https://grafana.com/api/dashboards/1860/revisions/latest/download" \
	  | sed 's/\$${ds_prometheus}/incus-prometheus/g' \
	  > /tmp/node-dashboard.json
	incus file push /tmp/node-dashboard.json \
	  cluster:grafana/var/lib/grafana/dashboards/nodes.json
	incus file push grafana/cluster-nodes.json \
	  cluster:grafana/var/lib/grafana/dashboards/cluster-nodes.json
	incus exec cluster:grafana -- rc-update add grafana default
	incus exec cluster:grafana -- rc-service grafana start

list: ## show running containers and access URLs
	@echo "=== Containers ==="
	@incus list cluster: --columns=n,s,4,l --format=compact 2>/dev/null \
	  | grep -E "^(prometheus|grafana)" || echo "  none running"
	@echo ""
	@echo "=== URLs ==="
	@terraform output 2>/dev/null | grep -E "url\s*=" || echo "  (run 'make create' first)"

destroy: ## destroy containers and remove metrics cert from Incus trust
	terraform destroy -auto-approve
	@FP=$$(incus config trust list --format=json 2>/dev/null \
	  | python3 -c "import sys,json; \
	    [print(c['fingerprint']) for c in json.load(sys.stdin) \
	     if c.get('name')=='o11y-prometheus']" 2>/dev/null); \
	[ -n "$$FP" ] && incus config trust remove "$$FP" && echo "removed metrics cert" || true
