#!/bin/bash

# From examples/inference-scheduling
helmfile destroy -n ${NAMESPACE}

# Or uninstall manually
helm uninstall infra-inference-scheduling -n ${NAMESPACE}
helm uninstall gaie-inference-scheduling -n ${NAMESPACE}
helm uninstall ms-inference-scheduling -n ${NAMESPACE}