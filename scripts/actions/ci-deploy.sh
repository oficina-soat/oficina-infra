#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-lab}"
APPLY_K8S="${APPLY_K8S:-true}"
BOOTSTRAP_SERVICE_DATABASES="${BOOTSTRAP_SERVICE_DATABASES:-true}"
BOOTSTRAP_SERVICE_DATABASES_MODE="${BOOTSTRAP_SERVICE_DATABASES_MODE:-k8s}"
APPLY_MICROSERVICES="${APPLY_MICROSERVICES:-true}"
INSTALL_NEW_RELIC_OTEL_COLLECTOR="${INSTALL_NEW_RELIC_OTEL_COLLECTOR:-auto}"
UPSERT_NEW_RELIC_SECRET="${UPSERT_NEW_RELIC_SECRET:-true}"
START_RDS_ON_DEPLOY="${START_RDS_ON_DEPLOY:-false}"

RDS_REQUIRED_ON_DEPLOY="${START_RDS_ON_DEPLOY}"
if [[ "${BOOTSTRAP_SERVICE_DATABASES}" == "true" ]]; then
  RDS_REQUIRED_ON_DEPLOY="true"
fi

resolve_install_new_relic_otel_collector() {
  local install_mode="${INSTALL_NEW_RELIC_OTEL_COLLECTOR,,}"

  case "${install_mode}" in
    auto)
      if [[ -n "${NEW_RELIC_LICENSE_KEY:-}" ]]; then
        printf 'true'
      else
        printf 'false'
      fi
      ;;
    true|1|yes|y)
      printf 'true'
      ;;
    false|0|no|n|"")
      printf 'false'
      ;;
    *)
      fail "INSTALL_NEW_RELIC_OTEL_COLLECTOR deve ser true, false ou auto"
      ;;
  esac
}

INSTALL_NEW_RELIC_OTEL_COLLECTOR_RESOLVED="$(resolve_install_new_relic_otel_collector)"
KUBECONFIG_UPDATED="false"

require_cmd aws
require_cmd terraform

log "Validando identidade AWS"
aws sts get-caller-identity >/dev/null

if [[ "${RDS_REQUIRED_ON_DEPLOY}" == "true" ]]; then
  if [[ "${BOOTSTRAP_SERVICE_DATABASES}" == "true" && "${START_RDS_ON_DEPLOY}" != "true" ]]; then
    log "Bootstrap dos databases habilitado; garantindo que o RDS esteja disponivel"
  else
    log "Solicitando inicio do RDS em paralelo com a recriacao do EKS"
  fi
  "${SCRIPT_DIR}/ci-rds-power.sh" start
fi

if [[ "${INSTALL_NEW_RELIC_OTEL_COLLECTOR,,}" == "auto" ]]; then
  if [[ "${INSTALL_NEW_RELIC_OTEL_COLLECTOR_RESOLVED}" == "true" ]]; then
    log "New Relic OpenTelemetry Collector habilitado automaticamente por NEW_RELIC_LICENSE_KEY"
  else
    log "New Relic OpenTelemetry Collector ignorado no modo auto porque NEW_RELIC_LICENSE_KEY nao foi informado"
  fi
fi

if [[ "${INSTALL_NEW_RELIC_OTEL_COLLECTOR_RESOLVED}" == "true" && "${UPSERT_NEW_RELIC_SECRET,,}" == "true" ]]; then
  require_non_empty "${NEW_RELIC_LICENSE_KEY:-}" "NEW_RELIC_LICENSE_KEY"
fi

log "Aplicando Terraform do ambiente lab"
TERRAFORM_ACTION=apply "${SCRIPT_DIR}/ci-terraform.sh"

if [[ "${RDS_REQUIRED_ON_DEPLOY}" == "true" ]]; then
  "${SCRIPT_DIR}/ci-rds-power.sh" wait-available
fi

if [[ "${BOOTSTRAP_SERVICE_DATABASES}" == "true" && "${BOOTSTRAP_SERVICE_DATABASES_MODE}" == "k8s" ]] \
  || [[ "${APPLY_K8S}" == "true" ]] \
  || [[ "${APPLY_MICROSERVICES}" == "true" ]] \
  || [[ "${INSTALL_NEW_RELIC_OTEL_COLLECTOR_RESOLVED}" == "true" ]]; then
  require_cmd kubectl
  log "Atualizando kubeconfig do cluster ${EKS_CLUSTER_NAME}"
  aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"
  KUBECONFIG_UPDATED="true"
fi

if [[ "${BOOTSTRAP_SERVICE_DATABASES}" == "true" ]]; then
  case "${BOOTSTRAP_SERVICE_DATABASES_MODE}" in
    k8s)
      log "Executando bootstrap dos databases dos microsservicos dentro do EKS"
      "${REPO_ROOT}/scripts/manual/bootstrap-service-databases-k8s.sh"
      ;;
    local)
      log "Executando bootstrap dos databases dos microsservicos a partir do runner"
      "${REPO_ROOT}/scripts/manual/bootstrap-service-databases.sh"
      ;;
    *)
      fail "BOOTSTRAP_SERVICE_DATABASES_MODE deve ser k8s ou local"
      ;;
  esac
fi

if [[ "${APPLY_K8S}" == "true" ]]; then
  log "Aplicando overlay Kubernetes compartilhado"
  kubectl apply -k "${REPO_ROOT}/k8s/overlays/lab"
fi

if [[ "${APPLY_MICROSERVICES}" == "true" ]]; then
  log "Aplicando manifests Kubernetes dos microsservicos quando houver imagens ECR"
  "${REPO_ROOT}/scripts/manual/apply-microservices.sh"
fi

if [[ "${INSTALL_NEW_RELIC_OTEL_COLLECTOR_RESOLVED}" == "true" ]]; then
  log "Instalando New Relic OpenTelemetry Collector"
  SKIP_KUBECONFIG_UPDATE="${KUBECONFIG_UPDATED}" "${REPO_ROOT}/scripts/manual/install-new-relic-otel-collector.sh"
fi

log "Restaurando dependencias opcionais da UI quando seu state ja existir"
"${SCRIPT_DIR}/ci-ui-workload-lifecycle.sh" resume
