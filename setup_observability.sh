#!/bin/bash

# Exit on any error and treat unset variables as errors
set -e
set -u

# Configuration
export NAMESPACE=monitoring
GRAFANA_ADMIN_PASSWORD="ArcPassword123!!"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is required but not installed. Aborting."; exit 1; }
    command -v helm >/dev/null 2>&1 || { print_error "helm is required but not installed. Aborting."; exit 1; }
    
    # Check if cluster is accessible
    kubectl cluster-info >/dev/null 2>&1 || { print_error "Cannot connect to Kubernetes cluster. Aborting."; exit 1; }
    
    print_status "Prerequisites check passed."
}

# Function to create namespace if it doesn't exist
create_namespace() {
    print_status "Creating namespace '${NAMESPACE}' if it doesn't exist..."
    
    if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
        print_warning "Namespace '${NAMESPACE}' already exists."
    else
        kubectl create namespace "${NAMESPACE}"
        print_status "Namespace '${NAMESPACE}' created."
    fi
    
    # Wait for namespace to be ready (check if we can create resources in it)
    print_status "Verifying namespace '${NAMESPACE}' is ready..."
    local retries=0
    local max_retries=30
    while [ $retries -lt $max_retries ]; do
        if kubectl auth can-i create pods --namespace="${NAMESPACE}" >/dev/null 2>&1; then
            print_status "Namespace '${NAMESPACE}' is ready."
            break
        fi
        retries=$((retries + 1))
        sleep 2
    done
    
    if [ $retries -eq $max_retries ]; then
        print_error "Namespace '${NAMESPACE}' is not ready after ${max_retries} attempts."
        exit 1
    fi
}

# Function to wait for deployment to be ready
wait_for_deployment() {
    local deployment_name=$1
    local namespace=$2
    local timeout=${3:-300s}
    
    print_status "Waiting for deployment '${deployment_name}' to be ready..."
    kubectl wait --for=condition=available --timeout="${timeout}" deployment/"${deployment_name}" -n "${namespace}"
}

check_prerequisites
create_namespace

# Install Prometheus stack (includes Grafana)
print_status "Adding Prometheus community Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

print_status "Installing Prometheus stack with Grafana..."
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
  --set grafana.service.type=NodePort \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=10Gi \
  --wait \
  --timeout=10m

print_status "Prometheus stack installation completed."

# Wait for Prometheus operator to be ready before installing DCGM exporter
print_status "Waiting for Prometheus operator to be ready..."
wait_for_deployment "prometheus-stack-kube-prom-operator" "${NAMESPACE}" "300s"

# Setup GPU monitoring with DCGM exporter (fixed typo)
print_status "Setting up GPU monitoring with DCGM exporter..."
kubectl apply -n "${NAMESPACE}" -f https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/master/dcgm-exporter.yaml
kubectl apply -n "${NAMESPACE}" -f https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/master/service-monitor.yaml

print_status "DCGM exporter setup completed."

# Get service information
print_status "Getting service information..."

# Check if running on minikube
if kubectl config current-context | grep -q minikube; then
    print_status "Detected minikube environment."
    
    # Use kubectl port-forward approach instead of minikube service to avoid hanging
    if kubectl get svc prometheus-stack-grafana -n "${NAMESPACE}" >/dev/null 2>&1; then
        GRAFANA_NODEPORT=$(kubectl get svc prometheus-stack-grafana -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
        
        if [ -n "${GRAFANA_NODEPORT}" ] && [ -n "${MINIKUBE_IP}" ]; then
            print_status "Grafana is available at: http://${MINIKUBE_IP}:${GRAFANA_NODEPORT}"
            print_status "Alternatively, you can run: kubectl port-forward svc/prometheus-stack-grafana -n ${NAMESPACE} 3000:80"
        else
            print_warning "Could not determine Grafana access details."
            print_status "You can access Grafana by running: kubectl port-forward svc/prometheus-stack-grafana -n ${NAMESPACE} 3000:80"
            print_status "Then open: http://localhost:3000"
        fi
    else
        print_warning "Grafana service not found yet. It may still be starting up."
        print_status "Once ready, you can access it with: kubectl port-forward svc/prometheus-stack-grafana -n ${NAMESPACE} 3000:80"
    fi
else
    # For other environments, show NodePort information
    GRAFANA_NODEPORT=$(kubectl get svc prometheus-stack-grafana -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}')
    print_status "Grafana is running on NodePort: ${GRAFANA_NODEPORT}"
    print_status "Access Grafana at: http://<your-node-ip>:${GRAFANA_NODEPORT}"
fi

# Display login information
print_status "=== Grafana Login Information ==="
print_status "Username: admin"
print_status "Password: ${GRAFANA_ADMIN_PASSWORD}"
print_status "================================="

# Verify installations
print_status "Verifying installations..."

# Check if Prometheus is accessible
if kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=prometheus --no-headers | grep -q Running; then
    print_status "✓ Prometheus is running"
else
    print_warning "✗ Prometheus may not be running properly"
fi

# Check if Grafana is accessible
if kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=grafana --no-headers | grep -q Running; then
    print_status "✓ Grafana is running"
else
    print_warning "✗ Grafana may not be running properly"
fi

# Check if DCGM exporter is running (if GPU nodes exist)
if kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}' | grep -q '[1-9]'; then
    if kubectl get pods -n "${NAMESPACE}" -l app=nvidia-dcgm-exporter --no-headers | grep -q Running; then
        print_status "✓ DCGM exporter is running"
    else
        print_warning "✗ DCGM exporter may not be running properly"
    fi
else
    print_warning "No GPU nodes detected. DCGM exporter may not be necessary."
fi

# Label the ServiceMonitor for Prometheus scraping
kubectl label servicemonitor dcgm-exporter -n monitoring release=prometheus-stack

print_status "Setup completed successfully!"
print_status "Save the Grafana password: ${GRAFANA_ADMIN_PASSWORD}"