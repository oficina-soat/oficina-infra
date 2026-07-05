#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"
TERRAFORM_ACTION="${TERRAFORM_ACTION:-apply}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-lab}"
SHARED_INFRA_NAME="${SHARED_INFRA_NAME:-${EKS_CLUSTER_NAME}}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_KEY="${TF_STATE_KEY:-oficina/lab/infra/terraform.tfstate}"
TF_STATE_REGION="${TF_STATE_REGION:-${AWS_REGION}}"
TF_STATE_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE:-}"

usage() {
  cat <<EOF
Uso:
  $(basename "$0")

Variaveis suportadas:
  TERRAFORM_DIR             Diretorio do root module. Default: terraform/environments/lab
  TERRAFORM_ACTION          init|plan|apply|destroy|validate. Default: apply
  TF_STATE_BUCKET           Bucket S3 do backend remoto. Se vazio, deriva o bucket canonico
  TF_STATE_KEY              Key do state. Default: oficina/lab/infra/terraform.tfstate
  TF_STATE_REGION           Regiao do backend. Default: AWS_REGION ou us-east-1
  TF_STATE_DYNAMODB_TABLE   Tabela DynamoDB opcional para lock
EOF
}

aws_caller_account_id() {
  aws sts get-caller-identity --query 'Account' --output text
}

resolve_shared_infra_name() {
  if [[ -n "${TF_VAR_shared_infra_name:-}" ]]; then
    printf '%s\n' "${TF_VAR_shared_infra_name}"
    return
  fi

  if [[ -n "${SHARED_INFRA_NAME:-}" ]]; then
    printf '%s\n' "${SHARED_INFRA_NAME}"
    return
  fi

  if [[ -n "${TF_VAR_cluster_name:-}" ]]; then
    printf '%s\n' "${TF_VAR_cluster_name}"
    return
  fi

  if [[ -n "${EKS_CLUSTER_NAME:-}" ]]; then
    printf '%s\n' "${EKS_CLUSTER_NAME}"
    return
  fi

  printf 'eks-lab\n'
}

resolve_shared_bucket_name() {
  if [[ -n "${TF_VAR_terraform_shared_data_bucket_name:-}" ]]; then
    printf '%s\n' "${TF_VAR_terraform_shared_data_bucket_name}"
    return
  fi

  printf 'tf-shared-%s-%s-%s\n' \
    "$(resolve_shared_infra_name)" \
    "$(aws_caller_account_id)" \
    "${TF_STATE_REGION}"
}

resolve_effective_backend_bucket() {
  if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
    printf '%s\n' "${TF_STATE_BUCKET}"
    return
  fi

  resolve_shared_bucket_name
}

terraform_init() {
  if [[ "${TERRAFORM_ACTION}" == "validate" ]]; then
    terraform -chdir="${TERRAFORM_DIR}" init -backend=false -input=false
    return
  fi

  if [[ -z "${TF_STATE_BUCKET}" ]]; then
    require_cmd aws
  fi

  local effective_tf_state_bucket
  effective_tf_state_bucket="$(resolve_effective_backend_bucket)"

  if [[ -z "${TF_STATE_BUCKET}" ]]; then
    log "TF_STATE_BUCKET nao informado; usando bucket derivado ${effective_tf_state_bucket}"
  fi

  if [[ -z "${TF_VAR_terraform_shared_data_bucket_name:-}" ]]; then
    export TF_VAR_terraform_shared_data_bucket_name="${effective_tf_state_bucket}"
  fi

  local backend_args=(
    "-backend-config=bucket=${effective_tf_state_bucket}"
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
