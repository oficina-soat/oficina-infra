#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"

source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
DB_SSLMODE="${DB_SSLMODE:-require}"
MASTER_SECRET_ARN="${MASTER_SECRET_ARN:-}"
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-5432}"
MASTER_DB_USER="${MASTER_DB_USER:-}"
MASTER_DB_PASSWORD="${MASTER_DB_PASSWORD:-}"
OS_DB_PASSWORD="${OS_DB_PASSWORD:-}"
BILLING_DB_PASSWORD="${BILLING_DB_PASSWORD:-}"
STORE_IN_SECRETS_MANAGER="${STORE_IN_SECRETS_MANAGER:-true}"
DB_BOOTSTRAP_NAMESPACE="${DB_BOOTSTRAP_NAMESPACE:-default}"
DB_BOOTSTRAP_JOB_NAME="${DB_BOOTSTRAP_JOB_NAME:-oficina-service-database-bootstrap}"
DB_BOOTSTRAP_SECRET_NAME="${DB_BOOTSTRAP_SECRET_NAME:-oficina-service-database-bootstrap}"
DB_BOOTSTRAP_CONFIGMAP_NAME="${DB_BOOTSTRAP_CONFIGMAP_NAME:-oficina-service-database-bootstrap-scripts}"
DB_BOOTSTRAP_IMAGE="${DB_BOOTSTRAP_IMAGE:-postgres:16}"
DB_BOOTSTRAP_TIMEOUT="${DB_BOOTSTRAP_TIMEOUT:-300s}"

OS_DATABASE="oficina_os"
OS_USERNAME="oficina_os_user"
OS_SECRET_NAME="oficina/lab/database/oficina-os-service"
BILLING_DATABASE="oficina_billing"
BILLING_USERNAME="oficina_billing_user"
BILLING_SECRET_NAME="oficina/lab/database/oficina-billing-service"

usage() {
  cat <<EOF
Uso:
  $(basename "$0")

Variaveis suportadas:
  TERRAFORM_DIR                  Diretorio do root module Terraform. Default: terraform/environments/lab
  AWS_REGION                     Regiao AWS. Default: us-east-1
  MASTER_SECRET_ARN              Secret gerenciado do usuario master. Se ausente, tenta ler do terraform output
  DB_HOST                        Endpoint do RDS. Se ausente, tenta ler do terraform output ou do secret master
  DB_PORT                        Porta do RDS. Default: 5432
  MASTER_DB_USER                 Usuario master. Se ausente, tenta ler do secret master
  MASTER_DB_PASSWORD             Senha master. Se ausente, tenta ler do secret master
  OS_DB_PASSWORD                 Senha de oficina_os_user. Se ausente, gera uma senha
  BILLING_DB_PASSWORD            Senha de oficina_billing_user. Se ausente, gera uma senha
  STORE_IN_SECRETS_MANAGER       true|false. Default: true
  DB_SSLMODE                     SSL mode do psql. Default: require
  DB_BOOTSTRAP_NAMESPACE         Namespace do Job efemero. Default: default
  DB_BOOTSTRAP_IMAGE             Imagem com bash e psql. Default: postgres:16
  DB_BOOTSTRAP_TIMEOUT           Timeout do Job. Default: 300s
EOF
}

read_tf_output() {
  local name="$1"

  require_cmd terraform
  terraform -chdir="${TERRAFORM_DIR}" output -raw "${name}" 2>/dev/null || true
}

read_master_secret_json() {
  require_cmd aws

  aws secretsmanager get-secret-value \
    --region "${AWS_REGION}" \
    --secret-id "${MASTER_SECRET_ARN}" \
    --query SecretString \
    --output text
}

generate_password() {
  require_cmd openssl
  openssl rand -base64 48 | tr -d '\n' | tr '/+' '_-' | cut -c1-32
}

upsert_secret() {
  local secret_name="$1"
  local database="$2"
  local username="$3"
  local password="$4"
  local payload

  require_cmd aws
  require_cmd jq

  payload="$(jq -nc \
    --arg engine "postgres" \
    --arg host "${DB_HOST}" \
    --argjson port "${DB_PORT}" \
    --arg database "${database}" \
    --arg dbname "${database}" \
    --arg username "${username}" \
    --arg password "${password}" \
    --arg sslmode "${DB_SSLMODE}" \
    '{engine: $engine, host: $host, port: $port, database: $database, dbname: $dbname, username: $username, password: $password, sslmode: $sslmode}')"

  if aws secretsmanager describe-secret --region "${AWS_REGION}" --secret-id "${secret_name}" >/dev/null 2>&1; then
    aws secretsmanager put-secret-value \
      --region "${AWS_REGION}" \
      --secret-id "${secret_name}" \
      --secret-string "${payload}" >/dev/null
    return
  fi

  aws secretsmanager create-secret \
    --region "${AWS_REGION}" \
    --name "${secret_name}" \
    --secret-string "${payload}" >/dev/null
}

cleanup_k8s_objects() {
  kubectl delete job "${DB_BOOTSTRAP_JOB_NAME}" \
    --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
    --ignore-not-found \
    --wait=true \
    --timeout=60s >/dev/null 2>&1 || true

  kubectl delete secret "${DB_BOOTSTRAP_SECRET_NAME}" \
    --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
    --ignore-not-found >/dev/null 2>&1 || true

  kubectl delete configmap "${DB_BOOTSTRAP_CONFIGMAP_NAME}" \
    --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
    --ignore-not-found >/dev/null 2>&1 || true
}

show_job_diagnostics() {
  log "Logs do Job ${DB_BOOTSTRAP_JOB_NAME}"
  kubectl logs "job/${DB_BOOTSTRAP_JOB_NAME}" \
    --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
    --all-containers=true \
    --tail=-1 || true

  kubectl get pods \
    --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
    --selector "job-name=${DB_BOOTSTRAP_JOB_NAME}" || true

  kubectl describe pods \
    --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
    --selector "job-name=${DB_BOOTSTRAP_JOB_NAME}" || true
}

ensure_namespace() {
  if kubectl get namespace "${DB_BOOTSTRAP_NAMESPACE}" >/dev/null 2>&1; then
    log "Namespace ${DB_BOOTSTRAP_NAMESPACE} ja existe"
    return
  fi

  kubectl create namespace "${DB_BOOTSTRAP_NAMESPACE}"
}

create_bootstrap_secret() {
  kubectl create secret generic "${DB_BOOTSTRAP_SECRET_NAME}" \
    --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
    "--from-literal=AWS_REGION=${AWS_REGION}" \
    "--from-literal=DB_SSLMODE=${DB_SSLMODE}" \
    "--from-literal=DB_HOST=${DB_HOST}" \
    "--from-literal=DB_PORT=${DB_PORT}" \
    "--from-literal=MASTER_DB_USER=${MASTER_DB_USER}" \
    "--from-literal=MASTER_DB_PASSWORD=${MASTER_DB_PASSWORD}" \
    "--from-literal=OS_DB_PASSWORD=${OS_DB_PASSWORD}" \
    "--from-literal=BILLING_DB_PASSWORD=${BILLING_DB_PASSWORD}" \
    "--from-literal=STORE_IN_SECRETS_MANAGER=false" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
}

create_bootstrap_configmap() {
  kubectl create configmap "${DB_BOOTSTRAP_CONFIGMAP_NAME}" \
    --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
    "--from-file=bootstrap-service-databases.sh=${REPO_ROOT}/scripts/manual/bootstrap-service-databases.sh" \
    "--from-file=common.sh=${REPO_ROOT}/scripts/lib/common.sh" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
}

run_bootstrap_job() {
  kubectl apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: ${DB_BOOTSTRAP_JOB_NAME}
  namespace: ${DB_BOOTSTRAP_NAMESPACE}
  labels:
    app.kubernetes.io/name: service-database-bootstrap
    app.kubernetes.io/part-of: oficina
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        app.kubernetes.io/name: service-database-bootstrap
        app.kubernetes.io/part-of: oficina
    spec:
      restartPolicy: Never
      containers:
        - name: bootstrap
          image: ${DB_BOOTSTRAP_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/bash
            - -c
            - /bootstrap/scripts/manual/bootstrap-service-databases.sh
          envFrom:
            - secretRef:
                name: ${DB_BOOTSTRAP_SECRET_NAME}
          volumeMounts:
            - name: bootstrap-scripts
              mountPath: /bootstrap
              readOnly: true
      volumes:
        - name: bootstrap-scripts
          configMap:
            name: ${DB_BOOTSTRAP_CONFIGMAP_NAME}
            defaultMode: 0555
            items:
              - key: bootstrap-service-databases.sh
                path: scripts/manual/bootstrap-service-databases.sh
              - key: common.sh
                path: scripts/lib/common.sh
YAML
}

wait_for_bootstrap_job() {
  local complete_pid failed_pid complete_log failed_log

  complete_log="$(mktemp)"
  failed_log="$(mktemp)"

  kubectl wait \
    --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
    --for=condition=complete \
    --timeout="${DB_BOOTSTRAP_TIMEOUT}" \
    "job/${DB_BOOTSTRAP_JOB_NAME}" >"${complete_log}" 2>&1 &
  complete_pid=$!

  kubectl wait \
    --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
    --for=condition=failed \
    --timeout="${DB_BOOTSTRAP_TIMEOUT}" \
    "job/${DB_BOOTSTRAP_JOB_NAME}" >"${failed_log}" 2>&1 &
  failed_pid=$!

  while kill -0 "${complete_pid}" 2>/dev/null && kill -0 "${failed_pid}" 2>/dev/null; do
    sleep 1
  done

  if ! kill -0 "${complete_pid}" 2>/dev/null && wait "${complete_pid}"; then
    kill "${failed_pid}" >/dev/null 2>&1 || true
    wait "${failed_pid}" >/dev/null 2>&1 || true
    rm -f "${complete_log}" "${failed_log}"
    return 0
  fi

  kill "${complete_pid}" "${failed_pid}" >/dev/null 2>&1 || true
  wait "${complete_pid}" >/dev/null 2>&1 || true
  wait "${failed_pid}" >/dev/null 2>&1 || true
  rm -f "${complete_log}" "${failed_log}"
  return 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd kubectl

if [[ -z "${MASTER_SECRET_ARN}" && ( -z "${DB_HOST}" || -z "${DB_PORT}" || -z "${MASTER_DB_USER}" || -z "${MASTER_DB_PASSWORD}" ) ]]; then
  MASTER_SECRET_ARN="$(read_tf_output db_master_user_secret_arn)"
fi

if [[ -n "${MASTER_SECRET_ARN}" ]]; then
  require_cmd jq
  MASTER_SECRET_JSON="$(read_master_secret_json)"
  [[ -n "${DB_HOST}" ]] || DB_HOST="$(json_field "${MASTER_SECRET_JSON}" host)"
  [[ -n "${DB_PORT}" ]] || DB_PORT="$(json_field "${MASTER_SECRET_JSON}" port)"
  [[ -n "${MASTER_DB_USER}" ]] || MASTER_DB_USER="$(json_field "${MASTER_SECRET_JSON}" username)"
  [[ -n "${MASTER_DB_PASSWORD}" ]] || MASTER_DB_PASSWORD="$(json_field "${MASTER_SECRET_JSON}" password)"
fi

[[ -n "${DB_HOST}" ]] || DB_HOST="$(read_tf_output db_endpoint)"
[[ -n "${DB_PORT}" ]] || DB_PORT="$(read_tf_output db_port)"
[[ -n "${MASTER_DB_USER}" ]] || MASTER_DB_USER="$(read_tf_output db_username)"
[[ -n "${OS_DB_PASSWORD}" ]] || OS_DB_PASSWORD="$(generate_password)"
[[ -n "${BILLING_DB_PASSWORD}" ]] || BILLING_DB_PASSWORD="$(generate_password)"

require_non_empty "${DB_HOST}" "DB_HOST"
require_non_empty "${DB_PORT}" "DB_PORT"
require_non_empty "${MASTER_DB_USER}" "MASTER_DB_USER"
require_non_empty "${MASTER_DB_PASSWORD}" "MASTER_DB_PASSWORD"
require_non_empty "${OS_DB_PASSWORD}" "OS_DB_PASSWORD"
require_non_empty "${BILLING_DB_PASSWORD}" "BILLING_DB_PASSWORD"

log "Garantindo namespace ${DB_BOOTSTRAP_NAMESPACE} para bootstrap dos databases"
ensure_namespace

cleanup_k8s_objects
trap cleanup_k8s_objects EXIT
trap 'cleanup_k8s_objects; exit 130' INT
trap 'cleanup_k8s_objects; exit 143' TERM

log "Preparando Job Kubernetes ${DB_BOOTSTRAP_JOB_NAME} para acessar ${DB_HOST}:${DB_PORT}"
create_bootstrap_secret
create_bootstrap_configmap
run_bootstrap_job

if ! wait_for_bootstrap_job; then
  show_job_diagnostics
  fail "Bootstrap dos databases via Kubernetes Job falhou"
fi

kubectl logs "job/${DB_BOOTSTRAP_JOB_NAME}" \
  --namespace "${DB_BOOTSTRAP_NAMESPACE}" \
  --all-containers=true \
  --tail=-1 || true

if [[ "${STORE_IN_SECRETS_MANAGER}" == "true" ]]; then
  upsert_secret "${OS_SECRET_NAME}" "${OS_DATABASE}" "${OS_USERNAME}" "${OS_DB_PASSWORD}"
  upsert_secret "${BILLING_SECRET_NAME}" "${BILLING_DATABASE}" "${BILLING_USERNAME}" "${BILLING_DB_PASSWORD}"
  log "Secrets atualizados: ${OS_SECRET_NAME}, ${BILLING_SECRET_NAME}"
fi

log "Bootstrap concluido via Kubernetes Job sem expor o RDS fora da VPC"
