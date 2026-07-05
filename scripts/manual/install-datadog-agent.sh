#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-lab}"
DATADOG_NAMESPACE="${DATADOG_NAMESPACE:-datadog}"
DATADOG_HELM_RELEASE="${DATADOG_HELM_RELEASE:-datadog-agent}"
DATADOG_API_KEY_SECRET_NAME="${DATADOG_API_KEY_SECRET_NAME:-datadog-secret}"
DATADOG_API_KEY_SECRET_KEY="${DATADOG_API_KEY_SECRET_KEY:-api-key}"
DATADOG_LOCAL_SERVICE_NAME="${DATADOG_LOCAL_SERVICE_NAME:-datadog-agent}"
DATADOG_SITE="${DATADOG_SITE:-datadoghq.com}"
DATADOG_VALUES_FILE="${DATADOG_VALUES_FILE:-${REPO_ROOT}/k8s/components/datadog-agent/values.lab.yaml}"
UPSERT_DATADOG_SECRET="${UPSERT_DATADOG_SECRET:-true}"
SKIP_KUBECONFIG_UPDATE="${SKIP_KUBECONFIG_UPDATE:-false}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

require_cmd kubectl
require_cmd helm

[[ "${DATADOG_API_KEY_SECRET_KEY}" == "api-key" ]] || fail "DATADOG_API_KEY_SECRET_KEY deve permanecer api-key para compatibilidade com o chart Datadog"

if [[ "${SKIP_KUBECONFIG_UPDATE}" != "true" ]]; then
  require_cmd aws
  log "Atualizando kubeconfig do cluster ${EKS_CLUSTER_NAME}"
  aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"
fi

[[ -f "${DATADOG_VALUES_FILE}" ]] || fail "arquivo de values Datadog nao encontrado: ${DATADOG_VALUES_FILE}"

log "Garantindo namespace ${DATADOG_NAMESPACE}"
kubectl create namespace "${DATADOG_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if [[ "${UPSERT_DATADOG_SECRET}" == "true" ]]; then
  require_non_empty "${DATADOG_API_KEY:-}" "DATADOG_API_KEY"
  log "Criando ou atualizando Secret ${DATADOG_API_KEY_SECRET_NAME}"
  kubectl create secret generic "${DATADOG_API_KEY_SECRET_NAME}" \
    --namespace "${DATADOG_NAMESPACE}" \
    --from-literal="${DATADOG_API_KEY_SECRET_KEY}=${DATADOG_API_KEY}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
else
  log "Reutilizando Secret Kubernetes existente: ${DATADOG_API_KEY_SECRET_NAME}"
fi

rendered_values="$(mktemp)"
trap 'rm -f "${rendered_values}"' EXIT

sed \
  -e "s|DATADOG_SITE_PLACEHOLDER|$(escape_sed_replacement "${DATADOG_SITE}")|g" \
  -e "s|DATADOG_CLUSTER_NAME_PLACEHOLDER|$(escape_sed_replacement "${EKS_CLUSTER_NAME}")|g" \
  -e "s|DATADOG_API_KEY_SECRET_NAME_PLACEHOLDER|$(escape_sed_replacement "${DATADOG_API_KEY_SECRET_NAME}")|g" \
  -e "s|DATADOG_LOCAL_SERVICE_NAME_PLACEHOLDER|$(escape_sed_replacement "${DATADOG_LOCAL_SERVICE_NAME}")|g" \
  "${DATADOG_VALUES_FILE}" >"${rendered_values}"

log "Configurando repositorio Helm Datadog"
helm repo add datadog https://helm.datadoghq.com --force-update >/dev/null
helm repo update datadog >/dev/null

log "Instalando ou atualizando Datadog Agent"
helm upgrade --install "${DATADOG_HELM_RELEASE}" datadog/datadog \
  --namespace "${DATADOG_NAMESPACE}" \
  --create-namespace \
  --values "${rendered_values}" \
  --wait \
  --timeout "${HELM_TIMEOUT}"

log "Datadog Agent configurado"
printf 'OTEL_EXPORTER_OTLP_ENDPOINT=http://%s.%s.svc.cluster.local:4317\n' "${DATADOG_LOCAL_SERVICE_NAME}" "${DATADOG_NAMESPACE}"
printf 'OTEL_EXPORTER_OTLP_PROTOCOL=grpc\n'
