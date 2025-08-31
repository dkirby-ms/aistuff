#!/bin/bash

# This script sets up the LLM-D deployer on a local Kubernetes environment with Minikube and Docker, including GPU support. It is intended to be run on a fresh Ubuntu 24.04 install. It has been tested with WSL2 on Win11 with RTX5070.
git clone https://github.com/llm-d-incubation/llm-d-infra

# Start Minikube with Docker driver and GPU support
minikube start --driver=docker --container-runtime=docker --gpus=all

# Install dependencies for LLM-D
bash ./llm-d-infra/quickstart/dependencies/install-deps.sh

# Create kubernetes secret for huggingface token
# You need to create a token on https://huggingface.co/settings/tokens with read access to private models
# Then set it as an environment variable HF_TOKEN before running this script
export HF_TOKEN=""
export HF_TOKEN_NAME=${HF_TOKEN_NAME:-llm-d-hf-token}
export NAMESPACE=llmd-inference-scheduler # any namespace will do, but must match the one used in the helmfile below
kubectl create namespace ${NAMESPACE}
kubectl create secret generic ${HF_TOKEN_NAME} \
    --from-literal="HF_TOKEN=${HF_TOKEN}" \
    --namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Install gateway provider CRDs
bash ./llm-d-infra/quickstart/gateway-control-plane-providers/install-gateway-provider-dependencies.sh
helmfile apply -f ./llm-d-infra/quickstart/gateway-control-plane-providers/kgateway.helmfile.yaml

# Install LLM-D for inference scheduling
sed -i '/^decode:/,/^[a-zA-Z]/ s/  replicas: 2/  replicas: 1/' ./llm-d-infra/quickstart/examples/inference-scheduling/ms-inference-scheduling/values.yaml # hack for only one GPU
sed -i '/- '\''{"kv_connector":"NixlConnector", "kv_role":"kv_both"}'\''$/a\      - "--gpu-memory-utilization"\n      - "0.85"' ./llm-d-infra/quickstart/examples/inference-scheduling/ms-inference-scheduling/values.yaml
cd ./llm-d-infra/quickstart/examples/inference-scheduling
helmfile apply -e kgateway -n ${NAMESPACE}
kubectl apply -f httproute.yaml