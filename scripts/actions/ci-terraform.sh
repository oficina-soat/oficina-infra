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
BOOTSTRAP_TF_STATE_BUCKET="${BOOTSTRAP_TF_STATE_BUCKET:-true}"

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
  BOOTSTRAP_TF_STATE_BUCKET true|false para criar/configurar o bucket S3 antes do init. Default: true
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

create_s3_bucket() {
  local bucket="$1"
  local region="$2"

  if [[ "${region}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${bucket}" \
      --region "${region}" >/dev/null
    return
  fi

  aws s3api create-bucket \
    --bucket "${bucket}" \
    --region "${region}" \
    --create-bucket-configuration "LocationConstraint=${region}" >/dev/null
}

ensure_backend_bucket() {
  local bucket="$1"
  local region="$2"

  if aws s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1; then
    log "Bucket de state ${bucket} ja existe"
  else
    log "Bucket de state ${bucket} nao encontrado; criando em ${region}"
    create_s3_bucket "${bucket}" "${region}"
    aws s3api wait bucket-exists --bucket "${bucket}"
  fi

  log "Aplicando configuracoes seguras no bucket de state ${bucket}"
  aws s3api put-bucket-versioning \
    --bucket "${bucket}" \
    --versioning-configuration Status=Enabled >/dev/null

  aws s3api put-bucket-encryption \
    --bucket "${bucket}" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null

  aws s3api put-public-access-block \
    --bucket "${bucket}" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

  aws s3api put-bucket-ownership-controls \
    --bucket "${bucket}" \
    --ownership-controls '{"Rules":[{"ObjectOwnership":"BucketOwnerEnforced"}]}' >/dev/null
}

terraform_init() {
  if [[ "${TERRAFORM_ACTION}" == "validate" ]]; then
    terraform -chdir="${TERRAFORM_DIR}" init -backend=false -input=false
    return
  fi

  if [[ -z "${TF_STATE_BUCKET}" || "${BOOTSTRAP_TF_STATE_BUCKET}" == "true" ]]; then
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

  if [[ "${BOOTSTRAP_TF_STATE_BUCKET}" == "true" ]]; then
    ensure_backend_bucket "${effective_tf_state_bucket}" "${TF_STATE_REGION}"
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

case "${BOOTSTRAP_TF_STATE_BUCKET}" in
  true | false)
    ;;
  *)
    fail "BOOTSTRAP_TF_STATE_BUCKET deve ser true ou false"
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
