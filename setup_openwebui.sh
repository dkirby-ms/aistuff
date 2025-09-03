#!/bin/bash

# OpenWebUI Deployment Script for Minikube
# This script deploys OpenWebUI to work with existing LLM-D infrastructure

set -e

# Configuration
export NAMESPACE=${NAMESPACE:-openwebui}
export LLMD_NAMESPACE=${LLMD_NAMESPACE:-llmd}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="${SCRIPT_DIR}/openwebui-manifest.yaml"

echo "Setting up OpenWebUI to connect with LLM-D on Minikube..."

# Check if manifest file exists
if [[ ! -f "${MANIFEST_FILE}" ]]; then
    echo "Error: Manifest file not found at ${MANIFEST_FILE}"
    exit 1
fi

# Create namespace
echo "Creating namespace..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Generate and create secret for OpenWebUI
echo "Creating OpenWebUI secret..."
WEBUI_SECRET=$(openssl rand -hex 32)
kubectl create secret generic openwebui-secret \
    --from-literal=secret-key="${WEBUI_SECRET}" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Deploy OpenWebUI using the manifest file
echo "Deploying OpenWebUI from manifest..."
# Update namespace in manifest if different from default
sed "s/namespace: openwebui/namespace: ${NAMESPACE}/g" "${MANIFEST_FILE}" | \
sed "s|http://gateway.llmd.svc.cluster.local|http://gateway.${LLMD_NAMESPACE}.svc.cluster.local|g" | \
kubectl apply -f -

# Wait for OpenWebUI to be ready
echo "Waiting for OpenWebUI to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/openwebui -n ${NAMESPACE}

# Get access URL
echo ""
echo "=============================================="
echo "OpenWebUI deployment completed successfully!"
echo "=============================================="
echo ""
echo "Access OpenWebUI at:"
minikube service openwebui-service --url -n ${NAMESPACE}
echo ""
echo "Setup instructions:"
echo "1. Create an admin account on first visit"
echo "2. OpenWebUI is configured to use LLM-D as the backend"
echo "3. Models available through LLM-D will be accessible in the UI"
echo ""
echo "Available commands:"
echo "- View pods: kubectl get pods -n ${NAMESPACE}"
echo "- View services: kubectl get svc -n ${NAMESPACE}"
echo "- View logs: kubectl logs -f deployment/openwebui -n ${NAMESPACE}"
echo "- Check LLM-D status: kubectl get pods -n ${LLMD_NAMESPACE}"
echo ""
echo "Note: Make sure LLM-D is running before using OpenWebUI"
echo "Run './setup_llmd.sh' if you haven't set up LLM-D yet"
echo ""