#!/bin/bash

# This script sets up a local Kubernetes environment with Minikube and Docker, including GPU support. It is intended to be run on a fresh Ubuntu 24.04 install. It has been tested with WSL2 on Win11 with RTX5070.

# Validate nvidia drivers are installed
nvidia-smi # this should return a valid output showing your GPU details

# Install docker
sudo apt install -y docker.io
sudo usermod -aG docker $USER
newgrp docker

# Install minikube
sudo apt update && sudo apt install -y curl wget apt-transport-https

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client

# Install NVIDIA Container Toolkit
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

