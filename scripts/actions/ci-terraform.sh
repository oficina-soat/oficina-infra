#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"
TERRAFORM_ACTION="${TERRAFORM_ACTION:-apply}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_KEY="${TF_STATE_KEY:-oficina/lab/infra/terraform.tfstate}"
TF_STATE_REGION="${TF_STATE_REGION:-${AWS_REGION:-us-east-1}}"
TF_STATE_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE:-}"

usage() {
  cat <<EOF
Uso:
  $(basename "$0")

Variaveis suportadas:
  TERRAFORM_DIR             Diretorio do root module. Default: terraform/environments/lab
  TERRAFORM_ACTION          init|plan|apply|destroy|validate. Default: apply
  TF_STATE_BUCKET           Bucket S3 do backend remoto. Obrigatorio exceto para validate
  TF_STATE_KEY              Key do state. Default: oficina/lab/infra/terraform.tfstate
  TF_STATE_REGION           Regiao do backend. Default: AWS_REGION ou us-east-1
  TF_STATE_DYNAMODB_TABLE   Tabela DynamoDB opcional para lock
EOF
}

terraform_init() {
  if [[ "${TERRAFORM_ACTION}" == "validate" ]]; then
    terraform -chdir="${TERRAFORM_DIR}" init -backend=false -input=false
    return
  fi

  require_non_empty "${TF_STATE_BUCKET}" "TF_STATE_BUCKET"

  local backend_args=(
    "-backend-config=bucket=${TF_STATE_BUCKET}"
    "-backend-config=key=${TF_STATE_KEY}"
    "-backend-config=region=${TF_STATE_REGION}"
  )

  if [[ -n "${TF_STATE_DYNAMODB_TABLE}" ]]; then
    backend_args+=("-backend-config=dynamodb_table=${TF_STATE_DYNAMODB_TABLE}")
  fi

  terraform -chdir="${TERRAFORM_DIR}" init -input=false "${backend_args[@]}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd terraform

case "${TERRAFORM_ACTION}" in
  init | validate | plan | apply | destroy)
    ;;
  *)
    fail "TERRAFORM_ACTION deve ser init, validate, plan, apply ou destroy"
    ;;
esac

terraform fmt -check -recursive "${REPO_ROOT}/terraform"
terraform_init
terraform -chdir="${TERRAFORM_DIR}" validate

case "${TERRAFORM_ACTION}" in
  validate)
    ;;
  init)
    ;;
  plan)
    terraform -chdir="${TERRAFORM_DIR}" plan -input=false
    ;;
  apply)
    terraform -chdir="${TERRAFORM_DIR}" apply -auto-approve -input=false
    ;;
  destroy)
    terraform -chdir="${TERRAFORM_DIR}" destroy -auto-approve -input=false
    ;;
esac
