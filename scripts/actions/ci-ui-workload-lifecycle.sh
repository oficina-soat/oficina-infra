#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

ACTION="${1:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
TF_STATE_REGION="${TF_STATE_REGION:-${AWS_REGION}}"
TF_STATE_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE:-}"
MAIN_TF_STATE_KEY="${TF_STATE_KEY:-oficina/lab/infra/terraform.tfstate}"
UI_TF_STATE_KEY="${UI_TF_STATE_KEY:-oficina/lab/optional/ui-hosting/terraform.tfstate}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-lab}"
TERRAFORM_DIR="${REPO_ROOT}/terraform/optional/ui-hosting/lab"
RESTORE_UI_WORKLOAD="${RESTORE_UI_WORKLOAD:-true}"
UI_REPOSITORY_ROOT="${UI_REPOSITORY_ROOT:-${REPO_ROOT}/../oficina-ui}"

case "${ACTION}" in
  suspend)
    CREATE_UI_WORKLOAD=false
    ;;
  resume)
    CREATE_UI_WORKLOAD=true
    ;;
  *)
    fail "uso: $(basename "$0") suspend|resume"
    ;;
esac

require_cmd aws
require_cmd terraform

resolve_state_bucket() {
  if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
    printf '%s\n' "${TF_STATE_BUCKET}"
    return
  fi

  local account_id
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  printf 'tf-shared-%s-%s-%s\n' "${EKS_CLUSTER_NAME}" "${account_id}" "${TF_STATE_REGION}"
}

STATE_BUCKET="$(resolve_state_bucket)"

if ! aws s3api head-object --bucket "${STATE_BUCKET}" --key "${UI_TF_STATE_KEY}" >/dev/null 2>&1; then
  log "State opcional da UI nao encontrado; nenhuma dependencia externa para ${ACTION}"
  exit 0
fi

backend_args=(
  "-backend-config=bucket=${STATE_BUCKET}"
  "-backend-config=key=${UI_TF_STATE_KEY}"
  "-backend-config=region=${TF_STATE_REGION}"
)
if [[ -n "${TF_STATE_DYNAMODB_TABLE}" ]]; then
  backend_args+=("-backend-config=dynamodb_table=${TF_STATE_DYNAMODB_TABLE}")
fi

log "Inicializando state opcional da UI para ${ACTION}"
terraform -chdir="${TERRAFORM_DIR}" init -input=false -reconfigure "${backend_args[@]}"

log "Aplicando create_ui_workload=${CREATE_UI_WORKLOAD}; preservando ECR e telemetria da UI"
terraform -chdir="${TERRAFORM_DIR}" apply -input=false -auto-approve \
  -var="region=${AWS_REGION}" \
  -var="main_state_bucket=${STATE_BUCKET}" \
  -var="main_state_key=${MAIN_TF_STATE_KEY}" \
  -var="main_state_region=${TF_STATE_REGION}" \
  -var="create_ui_workload=${CREATE_UI_WORKLOAD}"

if [[ "${ACTION}" != "resume" || "${RESTORE_UI_WORKLOAD,,}" != "true" ]]; then
  exit 0
fi

if [[ ! -f "${UI_REPOSITORY_ROOT}/k8s/overlays/lab/kustomization.yaml" ]]; then
  log "Manifests do oficina-ui nao encontrados em ${UI_REPOSITORY_ROOT}; workload nao restaurado"
  exit 0
fi

require_cmd jq
require_cmd kubectl

ecr_repository_url="$(terraform -chdir="${TERRAFORM_DIR}" output -raw ecr_repository_url)"
ecr_repository_name="${ecr_repository_url#*/}"
ui_url="$(terraform -chdir="${TERRAFORM_DIR}" output -raw ui_url)"
observability_endpoint="$(terraform -chdir="${TERRAFORM_DIR}" output -raw ui_observability_endpoint)"
cluster_name="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name)"

if ! image_details="$(
  aws --region "${AWS_REGION}" ecr describe-images \
    --repository-name "${ecr_repository_name}" \
    --image-ids imageTag=latest \
    --query 'imageDetails[0]' \
    --output json 2>/dev/null
)" || [[ -z "${image_details}" || "${image_details}" == "null" ]]; then
  log "Imagem latest do oficina-ui nao encontrada em ${ecr_repository_name}; workload nao restaurado"
  exit 0
fi

revision="$(jq -r '[.imageTags[]? | select(. != "latest")][0] // "latest"' <<<"${image_details}")"
image="${ecr_repository_url}:latest"
runtime_directory="$(mktemp -d)"
trap 'rm -rf "${runtime_directory}"' EXIT

jq -n \
  --arg apiBaseUrl "${UI_API_BASE_URL:-${ui_url%/}/api/v1}" \
  --arg authBaseUrl "${UI_AUTH_BASE_URL:-${ui_url%/}}" \
  --arg observabilityEndpoint "${UI_OBSERVABILITY_ENDPOINT:-${observability_endpoint}}" \
  --arg release "${revision}" \
  '{apiBaseUrl: $apiBaseUrl, authBaseUrl: $authBaseUrl}
    + if $observabilityEndpoint == "" then {}
      else {observability: {
        endpoint: $observabilityEndpoint,
        environment: "lab",
        release: $release
      }}
      end' >"${runtime_directory}/runtime-config.json"
jq -n \
  --arg repository "oficina-soat/oficina-ui" \
  --arg revision "${revision}" \
  --arg runId "${GITHUB_RUN_ID:-resume-local}" \
  --arg deployedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{repository: $repository, revision: $revision, runId: $runId, deployedAt: $deployedAt}' \
  >"${runtime_directory}/deploy-metadata.json"

log "Atualizando kubeconfig para restaurar o workload do oficina-ui"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${cluster_name}" >/dev/null
kubectl create configmap oficina-ui-runtime \
  --from-file="runtime-config.json=${runtime_directory}/runtime-config.json" \
  --from-file="deploy-metadata.json=${runtime_directory}/deploy-metadata.json" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl kustomize "${UI_REPOSITORY_ROOT}/k8s/overlays/lab" \
  | sed "s|IMAGE_PLACEHOLDER|${image}|g" \
  | kubectl apply -f -
kubectl rollout restart deployment/oficina-ui
kubectl rollout status deployment/oficina-ui --timeout=300s
log "Workload do oficina-ui restaurado com a imagem latest ja publicada"
