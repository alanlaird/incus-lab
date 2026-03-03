# ── Metrics certificate (Prometheus → Incus /1.0/metrics auth) ───────────────
#
# Generates a TLS client cert, writes it to disk, and registers it with the
# Incus cluster as a read-only metrics certificate.  The key and cert are
# gitignored; the private key is stored in Terraform state (acceptable for a
# lab — it only grants read-only metrics access).

resource "tls_private_key" "metrics" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "metrics" {
  private_key_pem = tls_private_key.metrics.private_key_pem

  subject {
    common_name = "o11y-prometheus"
  }

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = false

  allowed_uses = [
    "digital_signature",
    "client_auth",
  ]
}

resource "local_file" "metrics_cert" {
  content  = tls_self_signed_cert.metrics.cert_pem
  filename = "${path.module}/metrics.crt"
}

resource "local_sensitive_file" "metrics_key" {
  content         = tls_private_key.metrics.private_key_pem
  filename        = "${path.module}/metrics.key"
  file_permission = "0600"
}

resource "null_resource" "register_metrics_cert" {
  depends_on = [local_file.metrics_cert]

  provisioner "local-exec" {
    command = <<-BASH
      FP=$(incus config trust list --format=json 2>/dev/null \
        | python3 -c "import sys,json; \
          [print(c['fingerprint']) for c in json.load(sys.stdin) \
           if c.get('name')=='o11y-prometheus']" 2>/dev/null)
      [ -n "$FP" ] && incus config trust remove "$FP" 2>/dev/null || true
      incus config trust add-certificate "${path.module}/metrics.crt" \
        --name=o11y-prometheus --type=metrics
    BASH
  }

  triggers = {
    cert = sha256(tls_self_signed_cert.metrics.cert_pem)
  }
}

# ── Prometheus config (generated with actual cluster node IPs) ────────────────

resource "local_file" "prometheus_config" {
  filename = "${path.module}/prometheus.yml"
  content  = <<-EOT
    global:
      scrape_interval: 15s

    scrape_configs:
      - job_name: incus
        metrics_path: /1.0/metrics
        scheme: https
        static_configs:
          - targets:
              - 172.16.11.141:8443
              - 172.16.11.142:8443
              - 172.16.11.143:8443
              - 172.16.11.144:8443
        tls_config:
          insecure_skip_verify: true
          cert_file: /etc/prometheus/metrics.crt
          key_file:  /etc/prometheus/metrics.key

      - job_name: prometheus
        static_configs:
          - targets: ['localhost:9090']
  EOT
}

# ── Grafana datasource (generated after Prometheus IP is known) ───────────────

resource "local_file" "grafana_datasource" {
  depends_on = [incus_instance.prometheus]
  filename   = "${path.module}/grafana/datasource.yml"
  content    = <<-EOT
    apiVersion: 1
    datasources:
      - name: Incus
        type: prometheus
        url: http://${coalesce(incus_instance.prometheus.ipv4_address, "pending")}:9090
        isDefault: true
        jsonData:
          timeInterval: 15s
  EOT
}

# ── Containers ────────────────────────────────────────────────────────────────

resource "incus_instance" "prometheus" {
  name   = "prometheus"
  image  = "images:alpine/3.21"
  type   = "container"
  remote = "cluster"

  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = "physnet"
    }
  }
}

resource "incus_instance" "grafana" {
  name   = "grafana"
  image  = "images:alpine/3.21"
  type   = "container"
  remote = "cluster"

  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = "physnet"
    }
  }
}
