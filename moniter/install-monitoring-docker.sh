#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
PROM_PORT=9090                 # Prometheus UI
GRAFANA_PORT=3000              # Grafana UI
EXPORTER_PORT=8000             # Python system metrics exporter (host)
EXPORTER_DIR="/mnt/external/sys-exporter"
GRAFANA_ADMIN_PASS="${GRAFANA_ADMIN_PASS:-ChangeMe123!}"  # override by exporting before run

# ---------- Ensure Docker is present ----------
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg docker.io docker-compose-plugin
  systemctl enable --now docker
fi

# ---------- Base packages for Python exporter (host-level metrics) ----------
apt-get update
apt-get install -y python3 python3-venv python3-pip lm-sensors
# Initialize sensors non-interactively (ok if it fails; exporter has fallbacks)
sensors-detect --auto >/dev/null 2>&1 || true

# ---------- Create a dedicated network ----------
docker network create monitoring >/dev/null 2>&1 || true

# ---------- Persistent storage on /mnt/external (ext4) ----------
mkdir -p /mnt/external/prometheus-conf
mkdir -p /mnt/external/prometheus-data
mkdir -p /mnt/external/grafana-data
mkdir -p "${EXPORTER_DIR}"

# Prometheus uses 'nobody' (65534); Grafana uses UID 472
chown -R 65534:65534 /mnt/external/prometheus-data
chown -R 472:472   /mnt/external/grafana-data

# ---------- Prometheus config (self + host exporter) ----------
cat > /mnt/external/prometheus-conf/prometheus.yml <<'YAML'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'system_metrics_exporter'
    static_configs:
      - targets: ['host.docker.internal:8000']
YAML

# ---------- Python system metrics exporter in /mnt/external ----------
if [ ! -d "${EXPORTER_DIR}/venv" ]; then
  python3 -m venv "${EXPORTER_DIR}/venv"
fi
"${EXPORTER_DIR}/venv"/bin/pip install --upgrade pip >/dev/null
"${EXPORTER_DIR}/venv"/bin/pip install psutil prometheus_client >/dev/null

cat > "${EXPORTER_DIR}/exporter.py" <<'PY'
#!/usr/bin/env python3
import time, os, glob
from prometheus_client import Gauge, start_http_server
import psutil

CPU_UTIL = Gauge("system_cpu_utilization_percent", "System-wide CPU utilization in percent")
MEM_UTIL = Gauge("system_memory_utilization_percent", "System memory utilized in percent")
CPU_TEMP = Gauge("system_cpu_temperature_celsius", "CPU temperature in Celsius")

def read_sysfs_temp():
    temps = []
    for path in glob.glob("/sys/class/thermal/thermal_zone*/temp"):
        try:
            with open(path, "r") as f:
                val = f.read().strip()
                if val and val.isdigit():
                    temps.append(int(val)/1000.0)
        except Exception:
            pass
    return max(temps) if temps else float("nan")

def get_cpu_temp():
    try:
        temps = psutil.sensors_temperatures()
        cands = []
        for _, entries in (temps or {}).items():
            for e in entries:
                if getattr(e, "current", None) is not None:
                    cands.append(e.current)
        if cands:
            return max(cands)
    except Exception:
        pass
    return read_sysfs_temp()

def main():
    port = int(os.environ.get("PORT", "8000"))
    interval = float(os.environ.get("SCRAPE_INTERVAL", "5"))
    start_http_server(port)
    while True:
        try:
            CPU_UTIL.set(psutil.cpu_percent(interval=None))
            MEM_UTIL.set(psutil.virtual_memory().percent)
            CPU_TEMP.set(get_cpu_temp())
        except Exception:
            pass
        time.sleep(interval)

if __name__ == "__main__":
    main()
PY
chmod +x "${EXPORTER_DIR}/exporter.py"

# ---------- systemd unit for exporter (waits for /mnt/external) ----------
cat > /etc/systemd/system/sys-exporter.service <<EOF
[Unit]
Description=System Metrics Exporter (Prometheus)
After=network-online.target
Wants=network-online.target
RequiresMountsFor=/mnt/external

[Service]
Type=simple
User=root
Environment=PORT=${EXPORTER_PORT}
Environment=SCRAPE_INTERVAL=5
WorkingDirectory=${EXPORTER_DIR}
ExecStart=${EXPORTER_DIR}/venv/bin/python ${EXPORTER_DIR}/exporter.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sys-exporter.service

# ---------- Run Prometheus (48h retention) ----------
docker rm -f prometheus >/dev/null 2>&1 || true
docker run -d --name prometheus --restart=always \
  --network monitoring \
  --add-host=host.docker.internal:host-gateway \
  -p ${PROM_PORT}:9090 \
  -v /mnt/external/prometheus-conf:/etc/prometheus:ro \
  -v /mnt/external/prometheus-data:/prometheus \
  prom/prometheus:latest \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus \
    --storage.tsdb.retention.time=48h

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
echo "Retention: 48h (two days)"
echo "Prometheus:  http://<server-ip>:${PROM_PORT}/"
echo "Grafana:     http://<server-ip>:${GRAFANA_PORT}/  (admin / ${GRAFANA_ADMIN_PASS})"
echo
echo "Custom exporter (host): http://<server-ip>:${EXPORTER_PORT}/metrics"
echo "Exporter code & venv: ${EXPORTER_DIR}"
echo "Prometheus scrapes job 'system_metrics_exporter'."
echo
echo "Persistent data dirs (ext4):"
echo "  /mnt/external/prometheus-conf   (config)"
echo "  /mnt/external/prometheus-data   (TSDB data)"
echo "  /mnt/external/grafana-data      (Grafana data)"
echo "==============================================="
