#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-lab}"
NEW_RELIC_NAMESPACE="${NEW_RELIC_NAMESPACE:-newrelic}"
NEW_RELIC_OTEL_COLLECTOR_HELM_RELEASE="${NEW_RELIC_OTEL_COLLECTOR_HELM_RELEASE:-nr-k8s-otel-collector}"
NEW_RELIC_OTEL_COLLECTOR_LOCAL_SERVICE_NAME="${NEW_RELIC_OTEL_COLLECTOR_LOCAL_SERVICE_NAME:-nr-k8s-otel-collector-gateway}"
NEW_RELIC_LICENSE_KEY_SECRET_NAME="${NEW_RELIC_LICENSE_KEY_SECRET_NAME:-new-relic-license-key}"
NEW_RELIC_LICENSE_KEY_SECRET_KEY="${NEW_RELIC_LICENSE_KEY_SECRET_KEY:-licenseKey}"
NEW_RELIC_CLUSTER_NAME="${NEW_RELIC_CLUSTER_NAME:-${EKS_CLUSTER_NAME}}"
NEW_RELIC_REGION="${NEW_RELIC_REGION:-US}"
NEW_RELIC_OTLP_ENDPOINT="${NEW_RELIC_OTLP_ENDPOINT:-https://otlp.nr-data.net}"
NEW_RELIC_VALUES_FILE="${NEW_RELIC_VALUES_FILE:-${REPO_ROOT}/k8s/components/new-relic-otel-collector/values.lab.yaml}"
UPSERT_NEW_RELIC_SECRET="${UPSERT_NEW_RELIC_SECRET:-true}"
SKIP_KUBECONFIG_UPDATE="${SKIP_KUBECONFIG_UPDATE:-false}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

require_cmd kubectl
require_cmd helm

if [[ "${NEW_RELIC_OTEL_COLLECTOR_LOCAL_SERVICE_NAME}" != "nr-k8s-otel-collector-gateway" ]]; then
  fail "NEW_RELIC_OTEL_COLLECTOR_LOCAL_SERVICE_NAME deve permanecer nr-k8s-otel-collector-gateway com o chart atual"
fi

if [[ "${SKIP_KUBECONFIG_UPDATE}" != "true" ]]; then
  require_cmd aws
  log "Atualizando kubeconfig do cluster ${EKS_CLUSTER_NAME}"
  aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"
fi

[[ -f "${NEW_RELIC_VALUES_FILE}" ]] || fail "arquivo de values New Relic nao encontrado: ${NEW_RELIC_VALUES_FILE}"

log "Garantindo namespace ${NEW_RELIC_NAMESPACE}"
kubectl create namespace "${NEW_RELIC_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if [[ "${UPSERT_NEW_RELIC_SECRET,,}" == "true" ]]; then
  require_non_empty "${NEW_RELIC_LICENSE_KEY:-}" "NEW_RELIC_LICENSE_KEY"
  log "Criando ou atualizando Secret ${NEW_RELIC_LICENSE_KEY_SECRET_NAME}"
  kubectl create secret generic "${NEW_RELIC_LICENSE_KEY_SECRET_NAME}" \
    --namespace "${NEW_RELIC_NAMESPACE}" \
    --from-literal="${NEW_RELIC_LICENSE_KEY_SECRET_KEY}=${NEW_RELIC_LICENSE_KEY}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
else
  log "Reutilizando Secret Kubernetes existente: ${NEW_RELIC_LICENSE_KEY_SECRET_NAME}"
fi

rendered_values="$(mktemp)"
rendered_manifest="$(mktemp)"
rendered_collector_config="$(mktemp)"
trap 'rm -f "${rendered_values}" "${rendered_manifest}" "${rendered_collector_config}"' EXIT

sed \
  -e "s|NEW_RELIC_CLUSTER_NAME_PLACEHOLDER|$(escape_sed_replacement "${NEW_RELIC_CLUSTER_NAME}")|g" \
  -e "s|NEW_RELIC_REGION_PLACEHOLDER|$(escape_sed_replacement "${NEW_RELIC_REGION}")|g" \
  -e "s|NEW_RELIC_LICENSE_KEY_SECRET_NAME_PLACEHOLDER|$(escape_sed_replacement "${NEW_RELIC_LICENSE_KEY_SECRET_NAME}")|g" \
  -e "s|NEW_RELIC_LICENSE_KEY_SECRET_KEY_PLACEHOLDER|$(escape_sed_replacement "${NEW_RELIC_LICENSE_KEY_SECRET_KEY}")|g" \
  -e "s|NEW_RELIC_OTLP_ENDPOINT_PLACEHOLDER|$(escape_sed_replacement "${NEW_RELIC_OTLP_ENDPOINT}")|g" \
  "${NEW_RELIC_VALUES_FILE}" >"${rendered_values}"

log "Configurando repositorio Helm New Relic"
helm repo add newrelic https://helm-charts.newrelic.com --force-update >/dev/null
helm repo update newrelic >/dev/null

log "Validando configuracao renderizada do New Relic OpenTelemetry Collector"
helm template "${NEW_RELIC_OTEL_COLLECTOR_HELM_RELEASE}" newrelic/nr-k8s-otel-collector \
  --namespace "${NEW_RELIC_NAMESPACE}" \
  --values "${rendered_values}" >"${rendered_manifest}"

require_cmd yq
NEW_RELIC_DEPLOYMENT_CONFIGMAP_NAME="${NEW_RELIC_OTEL_COLLECTOR_HELM_RELEASE}-deployment-config" \
  yq e -r \
  'select(.kind == "ConfigMap" and .metadata.name == strenv(NEW_RELIC_DEPLOYMENT_CONFIGMAP_NAME)) | .data."deployment-config.yaml"' \
  "${rendered_manifest}" >"${rendered_collector_config}"
[[ -s "${rendered_collector_config}" ]] || fail "ConfigMap do collector deployment nao foi renderizado pelo chart"
yq e '.' "${rendered_collector_config}" >/dev/null

cumulativetodelta_definition_count="$(
  awk '
    /^processors:$/ { in_processors = 1; next }
    in_processors && /^[^[:space:]]/ { in_processors = 0 }
    in_processors && /^  cumulativetodelta:$/ { count++ }
    END { print count + 0 }
  ' "${rendered_collector_config}"
)"
[[ "${cumulativetodelta_definition_count}" == "1" ]] || \
  fail "configuracao renderizada deve declarar processors.cumulativetodelta exatamente uma vez; encontrado ${cumulativetodelta_definition_count}"

log "Instalando ou atualizando New Relic OpenTelemetry Collector"
helm upgrade --install "${NEW_RELIC_OTEL_COLLECTOR_HELM_RELEASE}" newrelic/nr-k8s-otel-collector \
  --namespace "${NEW_RELIC_NAMESPACE}" \
  --create-namespace \
  --values "${rendered_values}" \
  --wait \
  --timeout "${HELM_TIMEOUT}"

log "New Relic OpenTelemetry Collector configurado"
printf 'OTEL_EXPORTER_OTLP_ENDPOINT=http://%s.%s.svc.cluster.local:4317\n' "${NEW_RELIC_OTEL_COLLECTOR_LOCAL_SERVICE_NAME}" "${NEW_RELIC_NAMESPACE}"
printf 'OTEL_EXPORTER_OTLP_PROTOCOL=grpc\n'
