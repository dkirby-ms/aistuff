#!/bin/bash

# Start Minikube with Docker driver and GPU support
minikube start --driver=docker --container-runtime=docker --gpus=all

# Install dependencies for LLM-D
curl -s https://raw.githubusercontent.com/llm-d-incubation/llm-d-infra/refs/heads/main/quickstart/dependencies/install-deps.sh | bash 

# Create kubernetes secret for huggingface token
# You need to create a token on https://huggingface.co/settings/tokens with read access to private models
# Then EXPORT it as HF_TOKEN in .env.local
source .env.local
export HF_TOKEN_NAME=${HF_TOKEN_NAME:-llm-d-hf-token}
export NAMESPACE=llmd # any namespace will do, but must match the one used in the helmfile below
kubectl create namespace ${NAMESPACE}
kubectl create secret generic ${HF_TOKEN_NAME} \
    --from-literal="HF_TOKEN=${HF_TOKEN}" \
    --namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Install gateway provider CRDs
curl -s https://raw.githubusercontent.com/llm-d-incubation/llm-d-infra/refs/heads/main/quickstart/gateway-control-plane-providers/install-gateway-provider-dependencies.sh | bash
helmfile apply -f https://raw.githubusercontent.com/llm-d-incubation/llm-d-infra/refs/heads/main/quickstart/gateway-control-plane-providers/kgateway.helmfile.yaml

