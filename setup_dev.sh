#!/bin/bash

# This script sets up a local Kubernetes environment with Minikube and Docker, including GPU support. 
# It is intended to be run on a fresh Ubuntu 24.04 install. 
# It has been tested with WSL2 on Win11 with RTX5070.

# Exit on any error and treat unset variables as errors
set -e
set -u

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect system resources
detect_resources() {
    local total_memory_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    local total_cpus=$(nproc)
    
    # Use 75% of available memory, minimum 4GB, maximum 16GB
    MINIKUBE_MEMORY=$((total_memory_gb * 3 / 4))
    if [ $MINIKUBE_MEMORY -lt 4 ]; then
        MINIKUBE_MEMORY=4
    elif [ $MINIKUBE_MEMORY -gt 16 ]; then
        MINIKUBE_MEMORY=16
    fi
    
    # Use 75% of available CPUs, minimum 2, maximum 8
    MINIKUBE_CPUS=$((total_cpus * 3 / 4))
    if [ $MINIKUBE_CPUS -lt 2 ]; then
        MINIKUBE_CPUS=2
    elif [ $MINIKUBE_CPUS -gt 8 ]; then
        MINIKUBE_CPUS=8
    fi
    
    print_status "Detected ${total_memory_gb}GB RAM, ${total_cpus} CPUs"
    print_status "Will allocate ${MINIKUBE_MEMORY}GB RAM and ${MINIKUBE_CPUS} CPUs to Minikube"
}

print_step "Starting development environment setup..."

# Validate nvidia drivers are installed
print_step "Validating NVIDIA drivers..."
if command_exists nvidia-smi; then
    if nvidia-smi >/dev/null 2>&1; then
        print_status "NVIDIA drivers are working correctly"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader,nounits
    else
        print_error "nvidia-smi command failed. Please install NVIDIA drivers first."
        exit 1
    fi
else
    print_error "nvidia-smi not found. Please install NVIDIA drivers first."
    exit 1
fi

# Detect system resources
detect_resources

# Update package lists
print_step "Updating package lists..."
sudo apt update

# Install Docker if not already installed
print_step "Installing Docker..."
if command_exists docker; then
    print_warning "Docker is already installed"
else
    sudo apt install -y docker.io
    print_status "Docker installed successfully"
fi

# Start and enable Docker service
print_status "Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

# Add user to docker group
print_status "Adding user to docker group..."
sudo usermod -aG docker $USER

# Check if user is in docker group and handle accordingly
if groups $USER | grep -q docker; then
    print_status "User is already in docker group"
else
    print_warning "User added to docker group. You may need to log out and back in for changes to take effect."
    print_status "Attempting to use docker with sudo for this session..."
fi

# Install required packages
print_step "Installing required packages..."
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release

# Install kubectl if not already installed
print_step "Installing kubectl..."
if command_exists kubectl; then
    print_warning "kubectl is already installed"
    kubectl version --client --short 2>/dev/null || true
else
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    print_status "kubectl installed successfully"
    kubectl version --client --short
fi

# Install Helm if not already installed
print_step "Installing Helm..."
if command_exists helm; then
    print_warning "Helm is already installed"
    helm version --short 2>/dev/null || true
else
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt update
    sudo apt install -y helm
    print_status "Helm installed successfully"
    helm version --short
fi

# Install Minikube if not already installed
print_step "Installing Minikube..."
if command_exists minikube; then
    print_warning "Minikube is already installed"
    minikube version --short 2>/dev/null || true
else
    curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube
    sudo mv minikube /usr/local/bin/
    print_status "Minikube installed successfully"
    minikube version --short
fi

# Install NVIDIA Container Toolkit
print_step "Installing NVIDIA Container Toolkit..."
if dpkg -l | grep -q nvidia-container-toolkit; then
    print_warning "NVIDIA Container Toolkit is already installed"
else
    # Add NVIDIA Container Toolkit repository
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
        && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
        && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
           sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
           sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    sudo apt update
    sudo apt install -y nvidia-container-toolkit
    print_status "NVIDIA Container Toolkit installed successfully"
fi

# Configure Docker for NVIDIA runtime
print_status "Configuring Docker for NVIDIA runtime..."
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Wait for Docker to restart
print_status "Waiting for Docker to restart..."
sleep 5

# Test Docker with NVIDIA runtime
print_status "Testing Docker with NVIDIA runtime..."
if groups $USER | grep -q docker; then
    # User is in docker group, can run without sudo
    if docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi >/dev/null 2>&1; then
        print_status "✓ Docker NVIDIA runtime test successful"
    else
        print_warning "Docker NVIDIA runtime test failed, but continuing..."
    fi
else
    # User not in docker group yet, use sudo
    if sudo docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi >/dev/null 2>&1; then
        print_status "✓ Docker NVIDIA runtime test successful (using sudo)"
    else
        print_warning "Docker NVIDIA runtime test failed, but continuing..."
    fi
fi

# Stop any existing minikube cluster
print_step "Preparing Minikube..."
if minikube status >/dev/null 2>&1; then
    print_warning "Existing Minikube cluster found. Stopping it..."
    minikube stop || true
    minikube delete || true
fi

# Start Minikube with Docker driver and GPU support
print_step "Starting Minikube with GPU support..."
print_status "Starting with ${MINIKUBE_MEMORY}GB memory and ${MINIKUBE_CPUS} CPUs..."

minikube start \
    --driver=docker \
    --container-runtime=docker \
    --gpus=all \
    --memory="${MINIKUBE_MEMORY}g" \
    --cpus="${MINIKUBE_CPUS}" \
    --kubernetes-version=stable

print_status "Minikube started successfully"

# Verify cluster is working
print_step "Verifying cluster setup..."
kubectl cluster-info
kubectl get nodes

# Check if GPU support is available in the cluster
print_step "Checking GPU support in cluster..."
if kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}' | grep -q '[1-9]'; then
    print_status "✓ GPU resources detected in Kubernetes cluster"
    kubectl get nodes -o custom-columns="NODE:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu"
else
    print_warning "No GPU resources detected in cluster. GPU support may not be properly configured."
fi

# Enable useful Minikube addons
print_step "Enabling useful Minikube addons..."
minikube addons enable dashboard
minikube addons enable metrics-server
print_status "Addons enabled: dashboard, metrics-server"

# Final verification and instructions
print_step "Setup completed successfully!"
echo
print_status "=== Setup Summary ==="
print_status "✓ NVIDIA drivers: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)"
print_status "✓ Docker: $(docker --version | cut -d' ' -f3 | sed 's/,//')"
print_status "✓ kubectl: $(kubectl version --client --short | cut -d' ' -f3)"
print_status "✓ Helm: $(helm version --short | cut -d' ' -f2)"
print_status "✓ Minikube: $(minikube version --short | cut -d' ' -f3)"
print_status "✓ Cluster: $(kubectl get nodes --no-headers | wc -l) node(s) ready"

echo
print_status "=== Next Steps ==="
print_status "1. Run 'kubectl get nodes' to verify your cluster"
print_status "2. Run 'minikube dashboard' to open the Kubernetes dashboard"
print_status "3. If you're not in the docker group yet, log out and back in"
print_status "4. Deploy your applications with GPU support using nvidia.com/gpu resources"

echo
print_status "Development environment setup is complete!"
