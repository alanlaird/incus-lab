output "container_ips" {
  description = "IPv4 addresses of the o11y containers"
  value = {
    prometheus = incus_instance.prometheus.ipv4_address
    grafana    = incus_instance.grafana.ipv4_address
  }
}

output "grafana_url" {
  description = "Grafana web UI — import dashboard ID 19727"
  value       = "http://${coalesce(incus_instance.grafana.ipv4_address, "pending")}:3000"
}

output "prometheus_url" {
  description = "Prometheus web UI"
  value       = "http://${coalesce(incus_instance.prometheus.ipv4_address, "pending")}:9090"
}
