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
