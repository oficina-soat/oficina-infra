#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"
TERRAFORM_ACTION="${TERRAFORM_ACTION:-apply}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-lab}"
SHARED_INFRA_NAME="${SHARED_INFRA_NAME:-${EKS_CLUSTER_NAME}}"
export TF_VAR_region="${TF_VAR_region:-${AWS_REGION}}"
export TF_VAR_cluster_name="${TF_VAR_cluster_name:-${EKS_CLUSTER_NAME}}"
export TF_VAR_shared_infra_name="${TF_VAR_shared_infra_name:-${SHARED_INFRA_NAME}}"
export TF_VAR_create_eks="${TF_VAR_create_eks:-true}"
export TF_VAR_deletion_protection="${TF_VAR_deletion_protection:-false}"
export TF_VAR_skip_final_snapshot="${TF_VAR_skip_final_snapshot:-true}"
export TF_VAR_delete_automated_backups="${TF_VAR_delete_automated_backups:-true}"
export TF_VAR_ecr_force_delete="${TF_VAR_ecr_force_delete:-false}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_KEY="${TF_STATE_KEY:-oficina/lab/infra/terraform.tfstate}"
TF_STATE_REGION="${TF_STATE_REGION:-${AWS_REGION}}"
TF_STATE_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE:-}"
BOOTSTRAP_TF_STATE_BUCKET="${BOOTSTRAP_TF_STATE_BUCKET:-true}"
TERRAFORM_OVERRIDE_VAR_FILE=""
declare -a TERRAFORM_OVERRIDE_VAR_ARGS=()

cleanup_terraform_override_var_file() {
  rm -f "${TERRAFORM_OVERRIDE_VAR_FILE:-}"
}

trap cleanup_terraform_override_var_file EXIT

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
  TF_VAR_create_eks         true|false para criar o EKS compartilhado. Default do script: true
  TF_VAR_deletion_protection true|false para proteger o RDS contra exclusao. Default do script: false
  TF_VAR_skip_final_snapshot true|false para pular snapshot final do RDS no destroy. Default do script: true
  TF_VAR_delete_automated_backups true|false para remover backups automaticos do RDS no destroy. Default do script: true
  TF_VAR_ecr_force_delete   true|false para destruir repositorios ECR com imagens. Default do script: false; em destroy: true
  DESTROY_ECR_IMAGES        true|false para remover imagens ECR antes do destroy. Default: true
  DESTROY_EXTERNAL_LAMBDAS  true|false para remover Lambdas externas que prendem ENIs da VPC. Default: true
  DESTROY_LAMBDA_ENI_WAIT_SECONDS segundos para aguardar liberacao de ENIs Lambda. Default/minimo: 3600
  DESTROY_LAMBDA_ENI_POLL_SECONDS intervalo entre consultas de ENIs Lambda. Default: 30
EOF
}

aws_caller_account_id() {
  aws sts get-caller-identity --query 'Account' --output text
}

prepare_terraform_override_var_file() {
  case "${TERRAFORM_ACTION}" in
    plan | apply | destroy) ;;
    *) return ;;
  esac

  require_cmd jq

  TERRAFORM_OVERRIDE_VAR_FILE="$(mktemp --suffix=.tfvars.json)"
  chmod 600 "${TERRAFORM_OVERRIDE_VAR_FILE}"
  jq -n '
    env
    | with_entries(select(.key | startswith("TF_VAR_")))
    | with_entries(.key |= ltrimstr("TF_VAR_"))
    | with_entries(.value |= (. as $value | try fromjson catch $value))
  ' >"${TERRAFORM_OVERRIDE_VAR_FILE}"
  TERRAFORM_OVERRIDE_VAR_ARGS=("-var-file=${TERRAFORM_OVERRIDE_VAR_FILE}")
}

is_truthy_value() {
  case "${1:-}" in
    true | TRUE | True | 1 | yes | YES | Yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_list_values() {
  local value="$1"

  if [[ -z "${value}" ]]; then
    return
  fi

  if [[ "${value}" == \[* ]]; then
    require_cmd jq
    jq -r '.[]' <<<"${value}"
    return
  fi

  tr ',;' '\n' <<<"${value}" | tr '[:space:]' '\n' | sed '/^$/d'
}

destroy_ecr_repository_names() {
  if [[ -n "${DESTROY_ECR_REPOSITORY_NAMES:-}" ]]; then
    normalize_list_values "${DESTROY_ECR_REPOSITORY_NAMES}"
    return
  fi

  if [[ -n "${TF_VAR_ecr_repository_names:-}" ]]; then
    normalize_list_values "${TF_VAR_ecr_repository_names}"
    return
  fi

  printf '%s\n' \
    oficina-os-service \
    oficina-billing-service \
    oficina-execution-service
}

destroy_lambda_function_names() {
  if [[ -n "${DESTROY_LAMBDA_FUNCTION_NAMES:-}" ]]; then
    normalize_list_values "${DESTROY_LAMBDA_FUNCTION_NAMES}"
    return
  fi

  printf '%s\n' \
    "${AUTH_LAMBDA_FUNCTION_NAME:-oficina-auth-lambda-lab}" \
    "${AUTH_SYNC_LAMBDA_FUNCTION_NAME:-oficina-auth-sync-lambda-lab}" \
    "${NOTIFICACAO_LAMBDA_FUNCTION_NAME:-oficina-notificacao-lambda-lab}" |
    sed '/^$/d'
}

resolve_role_arn_by_name_fragment() {
  local fragment="$1"

  aws iam list-roles \
    --query "Roles[?contains(RoleName, '${fragment}')].Arn | [0]" \
    --output text 2>/dev/null
}

resolve_role_arn_by_exact_name() {
  local role_name="$1"

  aws iam get-role \
    --role-name "${role_name}" \
    --query 'Role.Arn' \
    --output text 2>/dev/null || true
}

resolve_current_principal_arn() {
  local caller_arn assumed_role_name account_id

  caller_arn="$(aws sts get-caller-identity --query 'Arn' --output text)"

  if [[ "${caller_arn}" =~ ^arn:aws:sts::([0-9]{12}):assumed-role/([^/]+)/.+$ ]]; then
    account_id="${BASH_REMATCH[1]}"
    assumed_role_name="${BASH_REMATCH[2]}"
    printf 'arn:aws:iam::%s:role/%s\n' "${account_id}" "${assumed_role_name}"
    return
  fi

  printf '%s\n' "${caller_arn}"
}

validate_role_account_match() {
  local arn="$1"
  local label="$2"
  local current_account="$3"
  local arn_account=""

  if [[ "${arn}" =~ ^arn:aws:iam::([0-9]{12}):role/.+$ ]]; then
    arn_account="${BASH_REMATCH[1]}"
  fi

  if [[ -n "${arn_account}" && "${arn_account}" != "${current_account}" ]]; then
    fail "${label} aponta para a conta ${arn_account}, mas as credenciais AWS atuais estao na conta ${current_account}. Configure ${label} com uma role da mesma conta do runner."
  fi
}

set_eks_role_defaults() {
  local current_account current_principal_arn cluster_role_arn node_role_arn access_principal_arn

  if ! is_truthy_value "${TF_VAR_create_eks}"; then
    return
  fi

  require_cmd aws

  current_account="$(aws_caller_account_id)"
  current_principal_arn="$(resolve_current_principal_arn)"
  cluster_role_arn="${TF_VAR_eks_cluster_role_arn:-}"
  node_role_arn="${TF_VAR_eks_node_role_arn:-}"
  access_principal_arn="${TF_VAR_eks_access_principal_arn:-}"

  if [[ -z "${cluster_role_arn}" ]]; then
    cluster_role_arn="$(resolve_role_arn_by_name_fragment 'LabEksClusterRole')"

    if [[ -z "${cluster_role_arn}" || "${cluster_role_arn}" == "None" ]]; then
      fail "Nao foi possivel descobrir automaticamente a role do cluster EKS. Configure EKS_CLUSTER_ROLE_ARN nas vars do GitHub."
    fi

    export TF_VAR_eks_cluster_role_arn="${cluster_role_arn}"
    log "Usando role descoberta para o cluster EKS: ${cluster_role_arn}"
  fi

  if [[ -z "${node_role_arn}" ]]; then
    if [[ "${current_principal_arn}" =~ ^arn:aws:iam::[0-9]{12}:role/voclabs$ ]]; then
      node_role_arn="$(resolve_role_arn_by_exact_name 'LabRole')"

      if [[ -z "${node_role_arn}" || "${node_role_arn}" == "None" ]]; then
        fail "Sessao VocLabs detectada, mas a LabRole nao foi encontrada. Configure EKS_NODE_ROLE_ARN explicitamente com uma role que permita EKS, SNS, SQS e DynamoDB."
      fi

      log "VocLabs detectado; usando LabRole nos nodes EKS para disponibilizar SNS, SQS e DynamoDB sem attachments IAM proibidos: ${node_role_arn}"
    else
      node_role_arn="$(resolve_role_arn_by_name_fragment 'LabEksNodeRole')"
    fi

    if [[ -z "${node_role_arn}" || "${node_role_arn}" == "None" ]]; then
      fail "Nao foi possivel descobrir automaticamente a role dos nodes EKS. Configure EKS_NODE_ROLE_ARN nas vars do GitHub."
    fi

    export TF_VAR_eks_node_role_arn="${node_role_arn}"
    log "Usando role descoberta para os nodes EKS: ${node_role_arn}"
  fi

  if [[ -z "${access_principal_arn}" ]]; then
    access_principal_arn="${current_principal_arn}"
    export TF_VAR_eks_access_principal_arn="${access_principal_arn}"
    log "Usando principal de acesso ao cluster derivado das credenciais atuais: ${access_principal_arn}"
  fi

  validate_role_account_match "${TF_VAR_eks_cluster_role_arn}" "EKS_CLUSTER_ROLE_ARN" "${current_account}"
  validate_role_account_match "${TF_VAR_eks_node_role_arn}" "EKS_NODE_ROLE_ARN" "${current_account}"
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

prepare_destroy_defaults() {
  if [[ "${TERRAFORM_ACTION}" != "destroy" ]]; then
    return
  fi

  export TF_VAR_deletion_protection=false
  export TF_VAR_skip_final_snapshot=true
  export TF_VAR_delete_automated_backups=true
  export TF_VAR_ecr_force_delete=true
}

disable_rds_deletion_protection_for_destroy() {
  if [[ "${TERRAFORM_ACTION}" != "destroy" ]]; then
    return
  fi

  if ! is_truthy_value "${TF_VAR_create_rds:-true}"; then
    return
  fi

  require_cmd aws

  local db_identifier deletion_protection
  db_identifier="${TF_VAR_db_identifier:-oficina-postgres-lab}"

  if ! deletion_protection="$(
    aws --region "${AWS_REGION}" rds describe-db-instances \
      --db-instance-identifier "${db_identifier}" \
      --query 'DBInstances[0].DeletionProtection' \
      --output text 2>/dev/null
  )"; then
    log "Instancia RDS ${db_identifier} nao encontrada; seguindo com terraform destroy"
    return
  fi

  if [[ "${deletion_protection}" != "True" && "${deletion_protection}" != "true" ]]; then
    log "Protecao de exclusao do RDS ${db_identifier} ja esta desabilitada"
    return
  fi

  log "Desabilitando protecao de exclusao do RDS ${db_identifier} antes do destroy"
  aws --region "${AWS_REGION}" rds modify-db-instance \
    --db-instance-identifier "${db_identifier}" \
    --no-deletion-protection \
    --apply-immediately >/dev/null

  aws --region "${AWS_REGION}" rds wait db-instance-available \
    --db-instance-identifier "${db_identifier}"
}

suspend_optional_ui_for_destroy() {
  if [[ "${TERRAFORM_ACTION}" != "destroy" ]]; then
    return
  fi

  log "Removendo dependencias opcionais da UI sobre a rede principal antes do destroy"
  "${SCRIPT_DIR}/ci-ui-workload-lifecycle.sh" suspend
}

delete_ecr_repository_images_for_destroy() {
  if [[ "${TERRAFORM_ACTION}" != "destroy" ]]; then
    return
  fi

  if ! is_truthy_value "${DESTROY_ECR_IMAGES:-true}"; then
    log "Limpeza preventiva de imagens ECR desabilitada"
    return
  fi

  require_cmd aws
  require_cmd jq

  local repository image_ids total offset chunk
  while IFS= read -r repository; do
    [[ -n "${repository}" ]] || continue

    log "Removendo imagens ECR de ${repository} antes do destroy"

    if ! image_ids="$(
      aws --region "${AWS_REGION}" ecr list-images \
        --repository-name "${repository}" \
        --filter tagStatus=ANY \
        --query 'imageIds' \
        --output json 2>/dev/null
    )"; then
      log "Repositorio ECR ${repository} nao encontrado; seguindo"
      continue
    fi

    total="$(jq 'length' <<<"${image_ids}")"
    if ((total == 0)); then
      log "Repositorio ECR ${repository} ja esta vazio"
      continue
    fi

    offset=0
    while ((offset < total)); do
      chunk="$(jq -c --argjson offset "${offset}" '.[$offset:($offset + 100)]' <<<"${image_ids}")"
      aws --region "${AWS_REGION}" ecr batch-delete-image \
        --repository-name "${repository}" \
        --image-ids "${chunk}" >/dev/null
      offset=$((offset + 100))
    done
  done < <(destroy_ecr_repository_names)
}

lambda_security_group_name_for_function() {
  local function_name="$1"

  case "${function_name}" in
    "${AUTH_LAMBDA_FUNCTION_NAME:-oficina-auth-lambda-lab}")
      printf '%s\n' "${AUTH_LAMBDA_SECURITY_GROUP_NAME:-${function_name}-sg}"
      ;;
    "${AUTH_SYNC_LAMBDA_FUNCTION_NAME:-oficina-auth-sync-lambda-lab}")
      printf '%s\n' "${AUTH_SYNC_LAMBDA_SECURITY_GROUP_NAME:-${function_name}-sg}"
      ;;
    "${NOTIFICACAO_LAMBDA_FUNCTION_NAME:-oficina-notificacao-lambda-lab}")
      printf '%s\n' "${NOTIFICACAO_LAMBDA_SECURITY_GROUP_NAME:-${EKS_CLUSTER_NAME}-notificacao-lambda}"
      ;;
    *)
      printf '%s\n' "${function_name}-sg"
      ;;
  esac
}

resolve_security_group_ids_by_name() {
  local group_name="$1"
  local vpc_id_filter=()

  if [[ -n "${TF_VAR_vpc_id:-}" ]]; then
    vpc_id_filter=("Name=vpc-id,Values=${TF_VAR_vpc_id}")
  fi

  aws --region "${AWS_REGION}" ec2 describe-security-groups \
    --filters "${vpc_id_filter[@]}" "Name=group-name,Values=${group_name}" \
    --query 'SecurityGroups[].GroupId' \
    --output text 2>/dev/null |
    tr '[:space:]' '\n' |
    sed '/^$/d'
}

list_security_group_network_interfaces() {
  local security_group_id="$1"

  aws --region "${AWS_REGION}" ec2 describe-network-interfaces \
    --filters "Name=group-id,Values=${security_group_id}" \
    --query 'NetworkInterfaces[].NetworkInterfaceId' \
    --output text 2>/dev/null || true
}

require_positive_integer() {
  local value="$1"
  local name="$2"

  if ! [[ "${value}" =~ ^[0-9]+$ ]] || ((value == 0)); then
    fail "${name} deve ser um inteiro positivo"
  fi
}

wait_for_security_group_network_interfaces() {
  local security_group_id="$1"
  local wait_seconds="${DESTROY_LAMBDA_ENI_WAIT_SECONDS:-3600}"
  local poll_seconds="${DESTROY_LAMBDA_ENI_POLL_SECONDS:-30}"
  local min_wait_seconds=3600
  local deadline
  local interface_ids

  require_positive_integer "${wait_seconds}" "DESTROY_LAMBDA_ENI_WAIT_SECONDS"
  require_positive_integer "${poll_seconds}" "DESTROY_LAMBDA_ENI_POLL_SECONDS"

  if ((wait_seconds < min_wait_seconds)); then
    log "DESTROY_LAMBDA_ENI_WAIT_SECONDS=${wait_seconds} e menor que o minimo operacional ${min_wait_seconds}; usando ${min_wait_seconds}"
    wait_seconds="${min_wait_seconds}"
  fi

  deadline=$((SECONDS + wait_seconds))

  while true; do
    interface_ids="$(list_security_group_network_interfaces "${security_group_id}")"

    if [[ -z "${interface_ids}" || "${interface_ids}" == "None" ]]; then
      return
    fi

    if ((SECONDS >= deadline)); then
      fail "Security group ${security_group_id} ainda possui ENIs apos ${wait_seconds}s: ${interface_ids}"
    fi

    log "Aguardando liberacao de ENIs do security group ${security_group_id}: ${interface_ids}"
    sleep "${poll_seconds}"
  done
}

lambda_config_has_vpc() {
  local config_json="$1"

  jq -e '
    ((.VpcConfig.SecurityGroupIds // []) | length > 0)
    or ((.VpcConfig.SubnetIds // []) | length > 0)
  ' <<<"${config_json}" >/dev/null
}

wait_lambda_function_updated_for_destroy() {
  local function_name="$1"
  local output status

  set +e
  output="$(
    aws --region "${AWS_REGION}" lambda wait function-updated \
      --function-name "${function_name}" 2>&1
  )"
  status=$?
  set -e

  if [[ ${status} -ne 0 ]] && ! grep -Eq "ResourceNotFoundException|Function not found" <<<"${output}"; then
    echo "${output}" >&2
    exit "${status}"
  fi
}

detach_lambda_vpc_config_for_destroy() {
  local function_name="$1"
  local config_json="$2"
  local output status

  if ! lambda_config_has_vpc "${config_json}"; then
    return
  fi

  log "Removendo configuracao de VPC da Lambda ${function_name} antes da exclusao"

  set +e
  output="$(
    aws --region "${AWS_REGION}" lambda update-function-configuration \
      --function-name "${function_name}" \
      --vpc-config '{"SubnetIds":[],"SecurityGroupIds":[]}' 2>&1
  )"
  status=$?
  set -e

  if [[ ${status} -ne 0 ]]; then
    if grep -Eq "ResourceNotFoundException|Function not found" <<<"${output}"; then
      log "Lambda ${function_name} nao existe mais; seguindo"
      return
    fi

    echo "${output}" >&2
    exit "${status}"
  fi

  wait_lambda_function_updated_for_destroy "${function_name}"
}

revoke_ingress_rules_referencing_security_group() {
  local referenced_group_id="$1"
  local target_group_ids target_group_id target_group_json permissions

  require_cmd jq

  target_group_ids="$(
    aws --region "${AWS_REGION}" ec2 describe-security-groups \
      --filters "Name=ip-permission.group-id,Values=${referenced_group_id}" \
      --query 'SecurityGroups[].GroupId' \
      --output text 2>/dev/null || true
  )"

  for target_group_id in ${target_group_ids}; do
    target_group_json="$(
      aws --region "${AWS_REGION}" ec2 describe-security-groups \
        --group-ids "${target_group_id}" \
        --output json
    )"
    permissions="$(
      jq -c --arg group_id "${referenced_group_id}" '
        [
          .SecurityGroups[0].IpPermissions[] as $permission
          | ($permission.UserIdGroupPairs // [] | map(select(.GroupId == $group_id))) as $pairs
          | select($pairs | length > 0)
          | {
              IpProtocol: $permission.IpProtocol,
              UserIdGroupPairs: $pairs
            }
          | if $permission.FromPort == null then .
            else . + {FromPort: $permission.FromPort, ToPort: $permission.ToPort}
            end
        ]
      ' <<<"${target_group_json}"
    )"

    if [[ "$(jq 'length' <<<"${permissions}")" -eq 0 ]]; then
      continue
    fi

    log "Revogando regras de ingress que referenciam ${referenced_group_id} em ${target_group_id}"
    aws --region "${AWS_REGION}" ec2 revoke-security-group-ingress \
      --group-id "${target_group_id}" \
      --ip-permissions "${permissions}" >/dev/null
  done
}

delete_security_group_for_destroy() {
  local security_group_id="$1"

  [[ -n "${security_group_id}" ]] || return

  wait_for_security_group_network_interfaces "${security_group_id}"
  revoke_ingress_rules_referencing_security_group "${security_group_id}"

  log "Removendo security group externo ${security_group_id}"
  local output status
  set +e
  output="$(
    aws --region "${AWS_REGION}" ec2 delete-security-group \
      --group-id "${security_group_id}" 2>&1
  )"
  status=$?
  set -e

  if [[ ${status} -ne 0 ]] && ! grep -Eq "InvalidGroup.NotFound" <<<"${output}"; then
    echo "${output}" >&2
    exit "${status}"
  fi
}

delete_lambda_log_group_for_destroy() {
  local function_name="$1"
  local log_group_name="/aws/lambda/${function_name}"

  local output status
  set +e
  output="$(
    aws --region "${AWS_REGION}" logs delete-log-group \
      --log-group-name "${log_group_name}" 2>&1
  )"
  status=$?
  set -e

  if [[ ${status} -ne 0 ]] && ! grep -Eq "ResourceNotFoundException" <<<"${output}"; then
    echo "${output}" >&2
    exit "${status}"
  fi
}

delete_external_lambda_for_destroy() {
  local function_name="$1"
  local config_json security_group_ids security_group_name security_group_id

  log "Limpando Lambda externa ${function_name} antes do destroy"

  if config_json="$(
    aws --region "${AWS_REGION}" lambda get-function-configuration \
      --function-name "${function_name}" \
      --output json 2>/dev/null
  )"; then
    security_group_ids="$(jq -r '.VpcConfig.SecurityGroupIds[]?' <<<"${config_json}")"

    detach_lambda_vpc_config_for_destroy "${function_name}" "${config_json}"

    aws --region "${AWS_REGION}" lambda delete-function \
      --function-name "${function_name}" >/dev/null

    while aws --region "${AWS_REGION}" lambda get-function \
      --function-name "${function_name}" >/dev/null 2>&1; do
      log "Aguardando remocao da Lambda ${function_name}"
      sleep 5
    done
  else
    log "Lambda ${function_name} nao existe; seguindo"
    security_group_ids=""
  fi

  delete_lambda_log_group_for_destroy "${function_name}"

  if [[ -z "${security_group_ids}" ]]; then
    security_group_name="$(lambda_security_group_name_for_function "${function_name}")"
    security_group_ids="$(resolve_security_group_ids_by_name "${security_group_name}")"
  fi

  for security_group_id in ${security_group_ids}; do
    delete_security_group_for_destroy "${security_group_id}"
  done
}

delete_external_lambdas_for_destroy() {
  if [[ "${TERRAFORM_ACTION}" != "destroy" ]]; then
    return
  fi

  if ! is_truthy_value "${DESTROY_EXTERNAL_LAMBDAS:-true}"; then
    log "Limpeza preventiva de Lambdas externas desabilitada"
    return
  fi

  require_cmd aws
  require_cmd jq

  local function_name
  while IFS= read -r function_name; do
    [[ -n "${function_name}" ]] || continue
    delete_external_lambda_for_destroy "${function_name}"
  done < <(destroy_lambda_function_names)
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd terraform

case "${TERRAFORM_ACTION}" in
  init | validate | plan | apply | destroy) ;;
  *)
    fail "TERRAFORM_ACTION deve ser init, validate, plan, apply ou destroy"
    ;;
esac

case "${BOOTSTRAP_TF_STATE_BUCKET}" in
  true | false) ;;
  *)
    fail "BOOTSTRAP_TF_STATE_BUCKET deve ser true ou false"
    ;;
esac

prepare_destroy_defaults

terraform fmt -check -recursive "${REPO_ROOT}/terraform"

if [[ "${TERRAFORM_ACTION}" != "validate" ]]; then
  set_eks_role_defaults
fi

prepare_terraform_override_var_file
terraform_init
terraform -chdir="${TERRAFORM_DIR}" validate

case "${TERRAFORM_ACTION}" in
  validate) ;;
  init) ;;
  plan)
    terraform -chdir="${TERRAFORM_DIR}" plan -input=false "${TERRAFORM_OVERRIDE_VAR_ARGS[@]}"
    ;;
  apply)
    terraform -chdir="${TERRAFORM_DIR}" apply -auto-approve -input=false "${TERRAFORM_OVERRIDE_VAR_ARGS[@]}"
    ;;
  destroy)
    suspend_optional_ui_for_destroy
    delete_ecr_repository_images_for_destroy
    delete_external_lambdas_for_destroy
    disable_rds_deletion_protection_for_destroy
    terraform -chdir="${TERRAFORM_DIR}" destroy -auto-approve -input=false "${TERRAFORM_OVERRIDE_VAR_ARGS[@]}"
    ;;
esac
