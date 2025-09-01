#!/bin/bash
export NAMESPACE=monitoring
kubectl create namespace ${NAMESPACE}

# Install Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring

# Setup GPU monitoring with DGCM exporter
kubectl apply -n monitoring -f https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/master/dcgm-exporter.yaml
kubectl apply -n monitoring -f https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/master/service-monitor.yaml

# Install Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install grafana grafana/grafana \
  --namespace ${NAMESPACE} \
  --set persistence.enabled=true \
  --set adminPassword='YourSecurePassword' \
  --set service.type=NodePort \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
  --set datasources."datasources\.yaml".datasources[0].type=prometheus \
  --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090

# Forward the Grafana port to Windows host
minikube service grafana --url -n monitoring