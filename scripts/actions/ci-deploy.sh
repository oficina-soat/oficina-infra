#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-lab}"
APPLY_K8S="${APPLY_K8S:-true}"
BOOTSTRAP_SERVICE_DATABASES="${BOOTSTRAP_SERVICE_DATABASES:-true}"
INSTALL_DATADOG_AGENT="${INSTALL_DATADOG_AGENT:-false}"

require_cmd aws
require_cmd terraform

log "Validando identidade AWS"
aws sts get-caller-identity >/dev/null

log "Aplicando Terraform do ambiente lab"
TERRAFORM_ACTION=apply "${SCRIPT_DIR}/ci-terraform.sh"

if [[ "${BOOTSTRAP_SERVICE_DATABASES}" == "true" ]]; then
  log "Executando bootstrap dos databases dos microsservicos"
  "${REPO_ROOT}/scripts/manual/bootstrap-service-databases.sh"
fi

if [[ "${APPLY_K8S}" == "true" ]]; then
  require_cmd kubectl
  log "Atualizando kubeconfig do cluster ${EKS_CLUSTER_NAME}"
  aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"
  log "Aplicando overlay Kubernetes compartilhado"
  kubectl apply -k "${REPO_ROOT}/k8s/overlays/lab"
fi

if [[ "${INSTALL_DATADOG_AGENT}" == "true" ]]; then
  log "Instalando Datadog Agent"
  SKIP_KUBECONFIG_UPDATE="${APPLY_K8S}" "${REPO_ROOT}/scripts/manual/install-datadog-agent.sh"
fi
