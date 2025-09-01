#!/bin/bash
export NAMESPACE=llmd # namespace should match existing namespace where HF token secret is stored
cd ./inference-scheduling
helmfile apply -e kgateway -n ${NAMESPACE}
kubectl apply -f httproute.yaml

# Forward the port to Windows host
minikube service infra-inference-scheduling-inference-gateway --url -n llmd

