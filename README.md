# LLM-D Infrastructure Setup

This repository contains scripts and configuration files for setting up and deploying [LLM-D (Large Language Model Deployment)](https://github.com/llm-d) infrastructure on Kubernetes with GPU support.

## Overview

This setup is tested with WSL2 and Ubuntu 24.04 with an Nvidia RTX 5070 consumer-grade card. It should also work with other CUDA-supported Nvidia accelerators. The nvidia-smi tool will confirm if your WSL can see your accelerator.

1. Setup Minikube environment with Nvidia drivers

    ```shell
    chmod +x setup_dev.sh
    ./setup_dev.sh
    ```

1. Setup observability with Prometheus/grafana stack

    ```shell
    chmod +x setup_observability.sh
    ./setup_observability.sh
    ```

1. Setup llmd and inference scheduling example

    ```shell
    chmod +x setup_llmd.sh
    ./setup_llmd.sh
    ```

1. Forward ports to access services. This will require leaving the shell open while the port is forwarded to the Windows host.

    ```shell
    minikube service prometheus-stack-grafana -n monitoring --url
    ```

    ```shell
    minikube service openwebui -n openwebui --url
    ```