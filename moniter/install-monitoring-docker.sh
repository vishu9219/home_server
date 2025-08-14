#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
PROM_PORT=9090          # Prometheus UI
GRAFANA_PORT=3000       # Grafana UI
GRAFANA_ADMIN_PASS="${GRAFANA_ADMIN_PASS:-ChangeMe123!}"  # override by exporting before run

# ---------- Ensure Docker is present ----------
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg docker.io docker-compose-plugin
  systemctl enable --now docker
fi

# ---------- Create a dedicated network ----------
docker network create monitoring >/dev/null 2>&1 || true

# ---------- Persistent storage on /mnt/external (ext4) ----------
mkdir -p /mnt/external/prometheus-conf
mkdir -p /mnt/external/prometheus-data
mkdir -p /mnt/external/grafana-data

# Prometheus uses 'nobody' (65534); Grafana uses UID 472
chown -R 65534:65534 /mnt/external/prometheus-data
chown -R 472:472   /mnt/external/grafana-data

# ---------- Minimal Prometheus config (scrapes itself) ----------
cat > /mnt/external/prometheus-conf/prometheus.yml <<'YAML'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
YAML

# ---------- Run Prometheus ----------
docker rm -f prometheus >/dev/null 2>&1 || true
docker run -d --name prometheus --restart=always \
  --network monitoring \
  -p ${PROM_PORT}:9090 \
  -v /mnt/external/prometheus-conf:/etc/prometheus:ro \
  -v /mnt/external/prometheus-data:/prometheus \
  prom/prometheus:latest \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus

# ---------- Run Grafana ----------
docker rm -f grafana >/dev/null 2>&1 || true
docker run -d --name grafana --restart=always \
  --network monitoring \
  -p ${GRAFANA_PORT}:3000 \
  -v /mnt/external/grafana-data:/var/lib/grafana \
  -e GF_SECURITY_ADMIN_USER=admin \
  -e GF_SECURITY_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASS}" \
  grafana/grafana:latest

echo
echo "==============================================="
echo "✅ Prometheus and Grafana are up via Docker."
echo "Prometheus:  http://<server-ip>:${PROM_PORT}/"
echo "Grafana:     http://<server-ip>:${GRAFANA_PORT}/  (admin / ${GRAFANA_ADMIN_PASS})"
echo
echo "Persistent data dirs (ext4):"
echo "  /mnt/external/prometheus-conf   (config)"
echo "  /mnt/external/prometheus-data   (TSDB data)"
echo "  /mnt/external/grafana-data      (Grafana data)"
echo "==============================================="
