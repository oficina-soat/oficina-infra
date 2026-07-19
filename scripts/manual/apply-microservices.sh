#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"

# shellcheck source=scripts/lib/common.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
K8S_NAMESPACE="${K8S_NAMESPACE:-default}"
DB_SSLMODE="${DB_SSLMODE:-require}"
MICROSERVICE_NAMES="${MICROSERVICE_NAMES:-oficina-os-service oficina-billing-service oficina-execution-service}"
MICROSERVICE_REPOSITORIES_ROOT="${MICROSERVICE_REPOSITORIES_ROOT:-$(cd "${REPO_ROOT}/.." && pwd)}"
API_GATEWAY_NAME="${API_GATEWAY_NAME:-eks-lab-http-api}"
OFICINA_AUTH_ISSUER="${OFICINA_AUTH_ISSUER:-}"
OFICINA_AUTH_JWKS_URI="${OFICINA_AUTH_JWKS_URI:-}"
JWT_SECRET_NAME="${JWT_SECRET_NAME:-oficina/lab/jwt}"
JWT_SECRET_PUBLIC_KEY_FIELD="${JWT_SECRET_PUBLIC_KEY_FIELD:-publicKeyPem}"
K8S_JWT_SECRET_NAME="${K8S_JWT_SECRET_NAME:-oficina-jwt-keys}"
BILLING_MERCADO_PAGO_K8S_SECRET_NAME="${BILLING_MERCADO_PAGO_K8S_SECRET_NAME:-oficina-billing-service-mercado-pago-env}"
OFICINA_MERCADO_PAGO_ENABLED="${OFICINA_MERCADO_PAGO_ENABLED:-}"
OFICINA_MERCADO_PAGO_ACCESS_TOKEN="${OFICINA_MERCADO_PAGO_ACCESS_TOKEN:-}"
OFICINA_MERCADO_PAGO_WEBHOOK_SECRET="${OFICINA_MERCADO_PAGO_WEBHOOK_SECRET:-}"
OFICINA_MERCADO_PAGO_API_URL="${OFICINA_MERCADO_PAGO_API_URL:-}"
OFICINA_MERCADO_PAGO_API_MODE="${OFICINA_MERCADO_PAGO_API_MODE:-orders}"
OFICINA_MERCADO_PAGO_PAYER_EMAIL="${OFICINA_MERCADO_PAGO_PAYER_EMAIL:-}"
OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME="${OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME:-}"
WAIT_MICROSERVICE_ROLLOUT="${WAIT_MICROSERVICE_ROLLOUT:-false}"
MICROSERVICE_ROLLOUT_TIMEOUT="${MICROSERVICE_ROLLOUT_TIMEOUT:-300s}"

declare -a READY_SERVICES=()
declare -a SELECTED_SERVICES=()
declare -A SERVICE_IMAGES=()
declare -A SERVICE_RUNTIME_SECRET_CHECKSUMS=()
MICROSERVICE_TMP_DIR=""
JWT_SECRET_CHECKSUM=""

usage() {
  cat <<EOF
Uso:
  $(basename "$0")

Variaveis suportadas:
  AWS_REGION                    Regiao AWS. Default: us-east-1
  K8S_NAMESPACE                 Namespace Kubernetes. Default: default
  DB_SSLMODE                    SSL mode para URLs PostgreSQL. Default: require
  MICROSERVICE_NAMES            Servicos a aplicar, separados por espaco ou virgula. Default: todos
  MICROSERVICE_REPOSITORIES_ROOT Diretorio que contem os repositorios dos servicos. Default: pai do oficina-infra
  API_GATEWAY_NAME              Nome do HTTP API para descobrir issuer quando Terraform output nao estiver disponivel. Default: eks-lab-http-api
  OFICINA_AUTH_ISSUER           Issuer JWT. Se ausente, usa terraform output api_gateway_endpoint
  OFICINA_AUTH_JWKS_URI         JWKS URI. Se ausente, deriva de OFICINA_AUTH_ISSUER
  JWT_SECRET_NAME               Secret AWS com chave publica JWT. Default: oficina/lab/jwt
  JWT_SECRET_PUBLIC_KEY_FIELD   Campo da chave publica no secret JWT. Default: publicKeyPem
  K8S_JWT_SECRET_NAME           Secret Kubernetes com publicKey.pem. Default: oficina-jwt-keys
  BILLING_MERCADO_PAGO_K8S_SECRET_NAME Secret Kubernetes com variaveis Mercado Pago. Default: oficina-billing-service-mercado-pago-env
  OFICINA_MERCADO_PAGO_ENABLED  true|false para habilitar integracao Mercado Pago no billing
  OFICINA_MERCADO_PAGO_ACCESS_TOKEN Access Token Mercado Pago. No modo orders do lab, use a credencial de teste APP_USR
  OFICINA_MERCADO_PAGO_WEBHOOK_SECRET Secret de assinatura do webhook. Obrigatorio quando enabled=true
  OFICINA_MERCADO_PAGO_API_URL  URL da API Mercado Pago. Opcional; o servico possui default
  OFICINA_MERCADO_PAGO_API_MODE orders|payments. Default: orders; payments existe apenas para rollback
  OFICINA_MERCADO_PAGO_PAYER_EMAIL Email pagador sandbox. Opcional; o servico possui default
  OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME Nome pagador sandbox. APRO e exclusivo de lab/test
  OFICINA_OS_SERVICE_IMAGE      Imagem completa opcional do oficina-os-service
  OFICINA_BILLING_SERVICE_IMAGE Imagem completa opcional do oficina-billing-service
  OFICINA_EXECUTION_SERVICE_IMAGE Imagem completa opcional do oficina-execution-service
  WAIT_MICROSERVICE_ROLLOUT     true|false para aguardar rollout. Default: false
  MICROSERVICE_ROLLOUT_TIMEOUT  Timeout do rollout. Default: 300s
EOF
}

read_tf_output() {
  local name="$1"

  if ! command -v terraform >/dev/null 2>&1; then
    printf ''
    return
  fi

  terraform -chdir="${TERRAFORM_DIR}" output -raw "${name}" 2>/dev/null || true
}

read_api_gateway_endpoint() {
  local endpoint

  require_cmd aws
  endpoint="$(
    aws apigatewayv2 get-apis \
      --region "${AWS_REGION}" \
      --query "Items[?Name=='${API_GATEWAY_NAME}'].ApiEndpoint | [0]" \
      --output text 2>/dev/null || true
  )"

  if [[ -z "${endpoint}" || "${endpoint}" == "None" ]]; then
    printf ''
    return
  fi

  printf '%s' "${endpoint}"
}

read_secret_json() {
  local secret_name="$1"

  require_cmd aws
  aws secretsmanager get-secret-value \
    --region "${AWS_REGION}" \
    --secret-id "${secret_name}" \
    --query SecretString \
    --output text
}

secret_field() {
  local secret_json="$1"
  local field="$2"

  require_cmd jq
  jq -r --arg field "${field}" '.[$field] // empty' <<<"${secret_json}"
}

normalize_url() {
  local value="$1"

  while [[ -n "${value}" && "${value}" == */ ]]; do
    value="${value%/}"
  done

  printf '%s' "${value}"
}

normalize_bool() {
  local value="${1,,}"
  local default_value="$2"

  case "${value}" in
    true|1|yes|y)
      printf 'true'
      ;;
    false|0|no|n)
      printf 'false'
      ;;
    "")
      printf '%s' "${default_value}"
      ;;
    *)
      fail "$3 deve ser true ou false"
      ;;
  esac
}

normalize_mercado_pago_api_mode() {
  local value="${1,,}"

  case "${value}" in
    orders|payments)
      printf '%s' "${value}"
      ;;
    *)
      fail "OFICINA_MERCADO_PAGO_API_MODE deve ser orders ou payments"
      ;;
  esac
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

ensure_namespace() {
  if kubectl get namespace "${K8S_NAMESPACE}" >/dev/null 2>&1; then
    return
  fi

  kubectl create namespace "${K8S_NAMESPACE}"
}

apply_runtime_secret() {
  local k8s_secret_name="$1"

  kubectl apply \
    --server-side \
    --field-manager=oficina-runtime-secrets \
    -f -
  kubectl annotate secret "${k8s_secret_name}" \
    --namespace "${K8S_NAMESPACE}" \
    kubectl.kubernetes.io/last-applied-configuration- \
    >/dev/null 2>&1 || true
}

create_postgres_runtime_secret() {
  local aws_secret_name="$1"
  local k8s_secret_name="$2"
  local secret_json host port database username password

  secret_json="$(read_secret_json "${aws_secret_name}")"
  host="$(secret_field "${secret_json}" host)"
  port="$(secret_field "${secret_json}" port)"
  database="$(secret_field "${secret_json}" dbname)"
  [[ -n "${database}" ]] || database="$(secret_field "${secret_json}" database)"
  username="$(secret_field "${secret_json}" username)"
  password="$(secret_field "${secret_json}" password)"

  require_non_empty "${host}" "${aws_secret_name}.host"
  require_non_empty "${port}" "${aws_secret_name}.port"
  require_non_empty "${database}" "${aws_secret_name}.dbname"
  require_non_empty "${username}" "${aws_secret_name}.username"
  require_non_empty "${password}" "${aws_secret_name}.password"

  kubectl create secret generic "${k8s_secret_name}" \
    --namespace "${K8S_NAMESPACE}" \
    "--from-literal=DB_USERNAME=${username}" \
    "--from-literal=DB_PASSWORD=${password}" \
    "--from-literal=JDBC_DATABASE_URL=jdbc:postgresql://${host}:${port}/${database}?sslmode=${DB_SSLMODE}" \
    "--from-literal=REACTIVE_DATABASE_URL=postgresql://${host}:${port}/${database}?sslmode=${DB_SSLMODE}" \
    --dry-run=client \
    -o yaml | apply_runtime_secret "${k8s_secret_name}"
}

mercado_pago_runtime_configured() {
  [[ -n "${OFICINA_MERCADO_PAGO_ENABLED}" ]] \
    || [[ -n "${OFICINA_MERCADO_PAGO_ACCESS_TOKEN}" ]] \
    || [[ -n "${OFICINA_MERCADO_PAGO_WEBHOOK_SECRET}" ]] \
    || [[ -n "${OFICINA_MERCADO_PAGO_API_URL}" ]] \
    || [[ -n "${OFICINA_MERCADO_PAGO_PAYER_EMAIL}" ]] \
    || [[ -n "${OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME}" ]]
}

validate_billing_mercado_pago_config() {
  local api_mode enabled

  enabled="$(normalize_bool "${OFICINA_MERCADO_PAGO_ENABLED}" "false" "OFICINA_MERCADO_PAGO_ENABLED")"
  api_mode="$(normalize_mercado_pago_api_mode "${OFICINA_MERCADO_PAGO_API_MODE}")"

  if [[ "${enabled}" == "true" ]]; then
    require_non_empty "${OFICINA_MERCADO_PAGO_ACCESS_TOKEN}" "OFICINA_MERCADO_PAGO_ACCESS_TOKEN"
    require_non_empty "${OFICINA_MERCADO_PAGO_WEBHOOK_SECRET}" "OFICINA_MERCADO_PAGO_WEBHOOK_SECRET"

    if [[ "${api_mode}" == "orders" && "${OFICINA_MERCADO_PAGO_ACCESS_TOKEN^^}" == TEST-* ]]; then
      fail "OFICINA_MERCADO_PAGO_ACCESS_TOKEN deve usar a credencial de teste APP_USR da aplicacao no modo orders; credenciais TEST-* nao sao aceitas pela API Orders"
    fi
  fi

  if [[ "${OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME^^}" == "APRO" \
      && "${OFICINA_MERCADO_PAGO_PAYER_EMAIL,,}" != "test_user_br@testuser.com" ]]; then
    fail "OFICINA_MERCADO_PAGO_PAYER_EMAIL deve ser test_user_br@testuser.com no cenario APRO"
  fi
}

create_billing_mercado_pago_secret() {
  local api_mode enabled tmp_file

  validate_billing_mercado_pago_config
  enabled="$(normalize_bool "${OFICINA_MERCADO_PAGO_ENABLED}" "false" "OFICINA_MERCADO_PAGO_ENABLED")"
  api_mode="$(normalize_mercado_pago_api_mode "${OFICINA_MERCADO_PAGO_API_MODE}")"

  if [[ "${enabled}" != "true" ]] && ! mercado_pago_runtime_configured; then
    log "Mercado Pago nao configurado para o billing; secret ${BILLING_MERCADO_PAGO_K8S_SECRET_NAME} nao sera criado"
    return
  fi

  tmp_file="$(mktemp)"

  {
    printf 'OFICINA_MERCADO_PAGO_ENABLED=%s\n' "${enabled}"
    printf 'OFICINA_MERCADO_PAGO_API_MODE=%s\n' "${api_mode}"
    if [[ -n "${OFICINA_MERCADO_PAGO_ACCESS_TOKEN}" ]]; then
      printf 'OFICINA_MERCADO_PAGO_ACCESS_TOKEN=%s\n' "${OFICINA_MERCADO_PAGO_ACCESS_TOKEN}"
    fi
    if [[ -n "${OFICINA_MERCADO_PAGO_WEBHOOK_SECRET}" ]]; then
      printf 'OFICINA_MERCADO_PAGO_WEBHOOK_SECRET=%s\n' "${OFICINA_MERCADO_PAGO_WEBHOOK_SECRET}"
    fi
    if [[ -n "${OFICINA_MERCADO_PAGO_API_URL}" ]]; then
      printf 'OFICINA_MERCADO_PAGO_API_URL=%s\n' "${OFICINA_MERCADO_PAGO_API_URL}"
    fi
    if [[ -n "${OFICINA_MERCADO_PAGO_PAYER_EMAIL}" ]]; then
      printf 'OFICINA_MERCADO_PAGO_PAYER_EMAIL=%s\n' "${OFICINA_MERCADO_PAGO_PAYER_EMAIL}"
    fi
    if [[ -n "${OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME}" ]]; then
      printf 'OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME=%s\n' "${OFICINA_MERCADO_PAGO_PAYER_FIRST_NAME}"
    fi
  } > "${tmp_file}"

  if ! kubectl create secret generic "${BILLING_MERCADO_PAGO_K8S_SECRET_NAME}" \
    --namespace "${K8S_NAMESPACE}" \
    "--from-env-file=${tmp_file}" \
    --dry-run=client \
    -o yaml | apply_runtime_secret "${BILLING_MERCADO_PAGO_K8S_SECRET_NAME}"; then
    rm -f "${tmp_file}"
    return 1
  fi
  rm -f "${tmp_file}"
}

k8s_secret_data_checksum() {
  local k8s_secret_name="$1"

  require_cmd jq
  require_cmd sha256sum

  kubectl get secret "${k8s_secret_name}" \
    --namespace "${K8S_NAMESPACE}" \
    -o json \
    | jq -S -c '.data // {}' \
    | sha256sum \
    | awk '{print $1}'
}

record_runtime_secret_checksum() {
  local service="$1"
  local k8s_secret_name="$2"
  local checksum current

  checksum="$(k8s_secret_data_checksum "${k8s_secret_name}")"
  current="${SERVICE_RUNTIME_SECRET_CHECKSUMS[${service}]:-}"
  if [[ -n "${current}" ]]; then
    SERVICE_RUNTIME_SECRET_CHECKSUMS["${service}"]="${current}-${checksum}"
  else
    SERVICE_RUNTIME_SECRET_CHECKSUMS["${service}"]="${checksum}"
  fi
}

create_jwt_public_key_secret() {
  local jwt_secret_json public_key

  if ! jwt_secret_json="$(read_secret_json "${JWT_SECRET_NAME}" 2>/dev/null)"; then
    if [[ "${OFICINA_AUTH_JWKS_URI}" == file:* || "${OFICINA_AUTH_JWKS_URI}" == classpath:* ]]; then
      fail "secret JWT ${JWT_SECRET_NAME} nao encontrado para materializar ${K8S_JWT_SECRET_NAME}"
    fi

    log "Secret JWT ${JWT_SECRET_NAME} nao encontrado; seguindo com JWKS remoto ${OFICINA_AUTH_JWKS_URI}"
    return
  fi

  public_key="$(secret_field "${jwt_secret_json}" "${JWT_SECRET_PUBLIC_KEY_FIELD}")"
  if [[ -z "${public_key}" ]]; then
    if [[ "${OFICINA_AUTH_JWKS_URI}" == file:* || "${OFICINA_AUTH_JWKS_URI}" == classpath:* ]]; then
      fail "${JWT_SECRET_NAME}.${JWT_SECRET_PUBLIC_KEY_FIELD} deve ser informado para materializar ${K8S_JWT_SECRET_NAME}"
    fi

    log "Campo ${JWT_SECRET_PUBLIC_KEY_FIELD} ausente em ${JWT_SECRET_NAME}; seguindo com JWKS remoto ${OFICINA_AUTH_JWKS_URI}"
    return
  fi

  kubectl create secret generic "${K8S_JWT_SECRET_NAME}" \
    --namespace "${K8S_NAMESPACE}" \
    "--from-literal=publicKey.pem=${public_key}" \
    --dry-run=client \
    -o yaml | apply_runtime_secret "${K8S_JWT_SECRET_NAME}"
}

latest_ecr_image() {
  local repository_name="$1"
  local image_details repository_uri tag

  require_cmd aws
  require_cmd jq

  if ! image_details="$(
    aws ecr describe-images \
      --region "${AWS_REGION}" \
      --repository-name "${repository_name}" \
      --filter tagStatus=TAGGED \
      --output json 2>/dev/null
  )"; then
    printf ''
    return
  fi

  tag="$(
    jq -r '
      [.imageDetails[]? | select((.imageTags // []) | length > 0)]
      | sort_by(.imagePushedAt)
      | last
      | if . == null then "" else ((.imageTags | map(select(. != "latest")) | first) // .imageTags[0]) end
    ' <<<"${image_details}"
  )"

  if [[ -z "${tag}" || "${tag}" == "null" ]]; then
    printf ''
    return
  fi

  repository_uri="$(
    aws ecr describe-repositories \
      --region "${AWS_REGION}" \
      --repository-names "${repository_name}" \
      --query 'repositories[0].repositoryUri' \
      --output text
  )"

  if [[ -z "${repository_uri}" || "${repository_uri}" == "None" ]]; then
    printf ''
    return
  fi

  printf '%s:%s' "${repository_uri}" "${tag}"
}

service_image_env_name() {
  local service="$1"

  case "${service}" in
    oficina-os-service)
      printf 'OFICINA_OS_SERVICE_IMAGE'
      ;;
    oficina-billing-service)
      printf 'OFICINA_BILLING_SERVICE_IMAGE'
      ;;
    oficina-execution-service)
      printf 'OFICINA_EXECUTION_SERVICE_IMAGE'
      ;;
    *)
      fail "microsservico nao canonico: ${service}"
      ;;
  esac
}

resolve_selected_services() {
  local normalized service

  normalized="${MICROSERVICE_NAMES//,/ }"
  for service in ${normalized}; do
    case "${service}" in
      oficina-os-service | oficina-billing-service | oficina-execution-service)
        SELECTED_SERVICES+=("${service}")
        ;;
      *)
        fail "MICROSERVICE_NAMES contem microsservico nao canonico: ${service}"
        ;;
    esac
  done

  if [[ ${#SELECTED_SERVICES[@]} -eq 0 ]]; then
    fail "MICROSERVICE_NAMES deve conter ao menos um microsservico"
  fi
}

resolve_service_image() {
  local service="$1"
  local env_name="$2"
  local image="${!env_name:-}"

  if [[ -z "${image}" ]]; then
    image="$(latest_ecr_image "${service}")"
  fi

  if [[ -z "${image}" ]]; then
    log "Imagem de ${service} nao encontrada no ECR; manifest do servico sera ignorado nesta execucao"
    return
  fi

  READY_SERVICES+=("${service}")
  SERVICE_IMAGES["${service}"]="${image}"
}

prepare_service_manifest() {
  local service="$1"
  local image="$2"
  local target_dir="$3"
  local escaped_billing_mercado_pago_secret escaped_image escaped_issuer escaped_jwks

  local source_dir="${MICROSERVICE_REPOSITORIES_ROOT}/${service}/k8s/base"

  if [[ ! -d "${source_dir}" && "$(basename "${MICROSERVICE_REPOSITORIES_ROOT}")" == "${service}" ]]; then
    source_dir="${MICROSERVICE_REPOSITORIES_ROOT}/k8s/base"
  fi
  if [[ ! -f "${source_dir}/kustomization.yaml" ]]; then
    fail "base Kubernetes canonica de ${service} nao encontrada em ${source_dir}"
  fi

  cp -R "${source_dir}" "${target_dir}/${service}"

  escaped_billing_mercado_pago_secret="$(escape_sed_replacement "${BILLING_MERCADO_PAGO_K8S_SECRET_NAME}")"
  escaped_image="$(escape_sed_replacement "${image}")"
  escaped_issuer="$(escape_sed_replacement "${OFICINA_AUTH_ISSUER}")"
  escaped_jwks="$(escape_sed_replacement "${OFICINA_AUTH_JWKS_URI}")"

  sed -i \
    -e "s|IMAGE_PLACEHOLDER|${escaped_image}|g" \
    -e "s|OFICINA_AUTH_ISSUER_PLACEHOLDER|${escaped_issuer}|g" \
    -e "s|OFICINA_AUTH_JWKS_URI_PLACEHOLDER|${escaped_jwks}|g" \
    -e "s|BILLING_MERCADO_PAGO_K8S_SECRET_NAME_PLACEHOLDER|${escaped_billing_mercado_pago_secret}|g" \
    "${target_dir}/${service}"/*.yaml
}

apply_ready_manifests() {
  local service

  if [[ ${#READY_SERVICES[@]} -eq 0 ]]; then
    log "Nenhuma imagem de microsservico disponivel; nenhum Deployment de microsservico foi aplicado"
    return
  fi

  MICROSERVICE_TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${MICROSERVICE_TMP_DIR:-}"' EXIT

  {
    printf '%s\n' \
      "apiVersion: kustomize.config.k8s.io/v1beta1" \
      "kind: Kustomization" \
      "namespace: ${K8S_NAMESPACE}" \
      "resources:"
    for service in "${READY_SERVICES[@]}"; do
      printf '  - %s\n' "${service}"
    done
  } > "${MICROSERVICE_TMP_DIR}/kustomization.yaml"

  for service in "${READY_SERVICES[@]}"; do
    prepare_service_manifest "${service}" "${SERVICE_IMAGES[${service}]}" "${MICROSERVICE_TMP_DIR}"
  done

  log "Aplicando manifests dos microsservicos: ${READY_SERVICES[*]}"
  kubectl apply -k "${MICROSERVICE_TMP_DIR}"

  patch_ready_deployment_checksums

  if [[ "${WAIT_MICROSERVICE_ROLLOUT}" == "true" ]]; then
    for service in "${READY_SERVICES[@]}"; do
      kubectl rollout status \
        --namespace "${K8S_NAMESPACE}" \
        "deployment/${service}" \
        --timeout="${MICROSERVICE_ROLLOUT_TIMEOUT}"
    done
  fi
}

patch_deployment_checksum_annotations() {
  local service="$1"
  local runtime_secret_checksum="${SERVICE_RUNTIME_SECRET_CHECKSUMS[${service}]:-}"
  local patch

  if [[ -z "${JWT_SECRET_CHECKSUM}" && -z "${runtime_secret_checksum}" ]]; then
    return
  fi

  patch="$(
    jq -cn \
      --arg jwt_secret_checksum "${JWT_SECRET_CHECKSUM}" \
      --arg runtime_secret_checksum "${runtime_secret_checksum}" \
      '{
        spec: {
          template: {
            metadata: {
              annotations:
                ((if $jwt_secret_checksum != "" then
                    {"oficina.soat/jwt-secret-checksum": $jwt_secret_checksum}
                  else
                    {}
                  end)
                 + (if $runtime_secret_checksum != "" then
                    {"oficina.soat/runtime-secret-checksum": $runtime_secret_checksum}
                  else
                    {}
                  end))
            }
          }
        }
      }'
  )"

  log "Atualizando checksums de runtime no Deployment ${service}"
  kubectl patch deployment "${service}" \
    --namespace "${K8S_NAMESPACE}" \
    --type=merge \
    --patch "${patch}"
}

patch_ready_deployment_checksums() {
  local service

  for service in "${READY_SERVICES[@]}"; do
    patch_deployment_checksum_annotations "${service}"
  done
}

service_is_ready() {
  local expected="$1"
  local service

  for service in "${READY_SERVICES[@]}"; do
    if [[ "${service}" == "${expected}" ]]; then
      return 0
    fi
  done

  return 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd kubectl
require_cmd sed

resolve_selected_services

for service in "${SELECTED_SERVICES[@]}"; do
  resolve_service_image "${service}" "$(service_image_env_name "${service}")"
done

if [[ ${#READY_SERVICES[@]} -eq 0 ]]; then
  apply_ready_manifests
  exit 0
fi

if service_is_ready "oficina-billing-service"; then
  validate_billing_mercado_pago_config
fi

ensure_namespace

if [[ -z "${OFICINA_AUTH_ISSUER}" ]]; then
  OFICINA_AUTH_ISSUER="$(read_tf_output api_gateway_endpoint)"
fi
if [[ -z "${OFICINA_AUTH_ISSUER}" ]]; then
  OFICINA_AUTH_ISSUER="$(read_api_gateway_endpoint)"
fi
OFICINA_AUTH_ISSUER="$(normalize_url "${OFICINA_AUTH_ISSUER}")"
require_non_empty "${OFICINA_AUTH_ISSUER}" "OFICINA_AUTH_ISSUER"

if [[ -z "${OFICINA_AUTH_JWKS_URI}" ]]; then
  OFICINA_AUTH_JWKS_URI="${OFICINA_AUTH_ISSUER}/.well-known/jwks.json"
fi
OFICINA_AUTH_JWKS_URI="$(normalize_url "${OFICINA_AUTH_JWKS_URI}")"
require_non_empty "${OFICINA_AUTH_JWKS_URI}" "OFICINA_AUTH_JWKS_URI"

log "Criando ou atualizando secrets Kubernetes de runtime dos microsservicos"
create_jwt_public_key_secret
if kubectl get secret "${K8S_JWT_SECRET_NAME}" --namespace "${K8S_NAMESPACE}" >/dev/null 2>&1; then
  JWT_SECRET_CHECKSUM="$(k8s_secret_data_checksum "${K8S_JWT_SECRET_NAME}")"
fi

if service_is_ready "oficina-os-service"; then
  create_postgres_runtime_secret "oficina/lab/database/oficina-os-service" "oficina-os-service-database-env"
  record_runtime_secret_checksum "oficina-os-service" "oficina-os-service-database-env"
fi

if service_is_ready "oficina-billing-service"; then
  create_postgres_runtime_secret "oficina/lab/database/oficina-billing-service" "oficina-billing-service-database-env"
  record_runtime_secret_checksum "oficina-billing-service" "oficina-billing-service-database-env"
  create_billing_mercado_pago_secret
  if kubectl get secret "${BILLING_MERCADO_PAGO_K8S_SECRET_NAME}" --namespace "${K8S_NAMESPACE}" >/dev/null 2>&1; then
    record_runtime_secret_checksum "oficina-billing-service" "${BILLING_MERCADO_PAGO_K8S_SECRET_NAME}"
  fi
fi

apply_ready_manifests
