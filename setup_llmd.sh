#!/bin/bash

# Improved LLM-D Setup Script with Error Handling and Validation
set -euo pipefail  # Exit on errors, undefined variables, and pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' is not installed or not in PATH"
        return 1
    fi
    return 0
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    local missing_tools=()
    
    for tool in kubectl helmfile curl; do
        if ! check_command "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        exit 1
    fi
    
    log_info "All prerequisites satisfied"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Check for .env.dev file
    if [ -f ".env.dev" ]; then
        log_info "Found .env.dev file, sourcing it..."
        source .env.dev
    else
        log_warn ".env.dev file not found, expecting HF_TOKEN from environment"
    fi
    
    # Validate HF_TOKEN
    if [ -z "${HF_TOKEN:-}" ]; then
        log_error "HF_TOKEN environment variable is not set"
        log_error "Please create a Hugging Face token at https://huggingface.co/settings/tokens"
        log_error "and set it as: export HF_TOKEN='your_token_here'"
        exit 1
    fi
    
    # Set default values
    export HF_TOKEN_NAME=${HF_TOKEN_NAME:-llm-d-hf-token}
    export NAMESPACE=${NAMESPACE:-llmd}
    
    log_info "Environment variables loaded successfully"
    log_info "Using namespace: ${NAMESPACE}"
    log_info "Using HF token name: ${HF_TOKEN_NAME}"
}

# Function to install LLM-D dependencies
install_dependencies() {
    log_info "Installing LLM-D dependencies..."
    
    local deps_script_url="https://raw.githubusercontent.com/llm-d-incubation/llm-d-infra/refs/heads/main/quickstart/dependencies/install-deps.sh"
    
    if ! curl -sfL "$deps_script_url" | bash; then
        log_error "Failed to install LLM-D dependencies"
        exit 1
    fi
    
    log_info "LLM-D dependencies installed successfully"
}

# Function to create Kubernetes namespace and secret
setup_kubernetes_resources() {
    log_info "Setting up Kubernetes resources..."
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_error "Please ensure kubectl is configured and cluster is accessible"
        exit 1
    fi
    
    # Create namespace if it doesn't exist
    if kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        log_info "Namespace '${NAMESPACE}' already exists"
    else
        log_info "Creating namespace '${NAMESPACE}'..."
        if ! kubectl create namespace "${NAMESPACE}"; then
            log_error "Failed to create namespace '${NAMESPACE}'"
            exit 1
        fi
        log_info "Namespace '${NAMESPACE}' created successfully"
    fi
    
    # Wait a moment for namespace to be ready
    sleep 2
    
    # Create or update the Hugging Face token secret
    log_info "Creating/updating Hugging Face token secret..."
    if ! kubectl create secret generic "${HF_TOKEN_NAME}" \
        --from-literal="HF_TOKEN=${HF_TOKEN}" \
        --namespace "${NAMESPACE}" \
        --dry-run=client -o yaml | kubectl apply -f -; then
        log_error "Failed to create Hugging Face token secret"
        exit 1
    fi
    
    log_info "Kubernetes resources setup completed"
}

# Function to install gateway provider CRDs
install_gateway_providers() {
    log_info "Installing gateway provider CRDs..."
    
    local gateway_deps_url="https://raw.githubusercontent.com/llm-d-incubation/llm-d-infra/refs/heads/main/quickstart/gateway-control-plane-providers/install-gateway-provider-dependencies.sh"
    local kgateway_helmfile_url="https://raw.githubusercontent.com/llm-d-incubation/llm-d-infra/refs/heads/main/quickstart/gateway-control-plane-providers/kgateway.helmfile.yaml"
    
    # Install gateway provider dependencies
    if ! curl -sfL "$gateway_deps_url" | bash; then
        log_error "Failed to install gateway provider dependencies"
        exit 1
    fi
    
    # Apply kgateway helmfile
    if ! helmfile apply -f "$kgateway_helmfile_url"; then
        log_error "Failed to apply kgateway helmfile"
        exit 1
    fi
    
    log_info "Gateway provider CRDs installed successfully"
}

# Main execution function
main() {
    log_info "Starting LLM-D setup..."
    
    validate_prerequisites
    load_environment
    install_dependencies
    setup_kubernetes_resources
    install_gateway_providers
    
    log_info "LLM-D setup completed successfully!"
    log_info "Namespace: ${NAMESPACE}"
    log_info "HF Token Secret: ${HF_TOKEN_NAME}"
}

# Run main function with error handling
if ! main "$@"; then
    log_error "Setup failed. Please check the errors above and try again."
    exit 1
fi

