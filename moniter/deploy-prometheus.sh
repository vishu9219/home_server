#!/bin/bash
# deploy-prometheus.sh
# Usage: deploy-prometheus.sh
# Deploys Prometheus on MicroK8s with storage on /mnt/ext1/prometheus-data

set -euo pipefail

# Ensure external SSD is mounted
/usr/local/bin/mount-external-ssd.sh mount || true

PROM_PATH="/mnt/ext1/prometheus-data"
mkdir -p "$PROM_PATH"
sudo chown $USER:$USER "$PROM_PATH"

# Enable required addons
microk8s enable storage dns rbac helm3

# Create PV and PVC
cat <<EOF | microk8s kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata: { name: prometheus-pv }
spec:
  capacity: { storage: 50Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath: { path: "$PROM_PATH" }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: prometheus-pvc }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ""
  resources: { requests: { storage: 50Gi } }
EOF

# Deploy Prometheus via Helm chart
microk8s helm3 repo add prometheus-community https://prometheus-community.github.io/helm-charts
microk8s helm3 repo update
microk8s helm3 upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring --create-namespace \
  --set server.persistentVolume.existingClaim=prometheus-pvc

echo "Prometheus deployed in namespace 'monitoring'."
echo "Access: http://$(microk8s kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}'):9090"
