#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"

# shellcheck source=scripts/lib/common.sh
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
  TERRAFORM_DIR               Diretorio do root module Terraform. Default: terraform/environments/lab
  AWS_REGION                  Regiao AWS. Default: us-east-1
  MASTER_SECRET_ARN           Secret gerenciado do usuario master. Se ausente, tenta ler do terraform output
  DB_HOST                     Endpoint do RDS. Se ausente, tenta ler do terraform output ou do secret master
  DB_PORT                     Porta do RDS. Default: 5432
  MASTER_DB_USER              Usuario master. Se ausente, tenta ler do secret master
  MASTER_DB_PASSWORD          Senha master. Se ausente, tenta ler do secret master
  OS_DB_PASSWORD              Senha de oficina_os_user. Se ausente, gera uma senha
  BILLING_DB_PASSWORD         Senha de oficina_billing_user. Se ausente, gera uma senha
  STORE_IN_SECRETS_MANAGER    true|false. Default: true
  DB_SSLMODE                  SSL mode do psql. Default: require
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

bootstrap_database() {
  local database="$1"
  local username="$2"
  local password="$3"

  PGPASSWORD="${MASTER_DB_PASSWORD}" psql \
    "host=${DB_HOST} port=${DB_PORT} dbname=postgres user=${MASTER_DB_USER} sslmode=${DB_SSLMODE}" \
    -v ON_ERROR_STOP=1 \
    --set=database="${database}" \
    --set=username="${username}" \
    --set=password="${password}" \
    <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION', :'username', :'password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'username')\gexec

SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'username', :'password')\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'database', :'username')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'database')\gexec

SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', :'database')\gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'database', :'username')\gexec
SQL

  PGPASSWORD="${MASTER_DB_PASSWORD}" psql \
    "host=${DB_HOST} port=${DB_PORT} dbname=${database} user=${MASTER_DB_USER} sslmode=${DB_SSLMODE}" \
    -v ON_ERROR_STOP=1 \
    --set=username="${username}" \
    <<'SQL'
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO :"username";
ALTER SCHEMA public OWNER TO :"username";
SQL
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd psql

if [[ -z "${MASTER_SECRET_ARN}" && (-z "${DB_HOST}" || -z "${DB_PORT}" || -z "${MASTER_DB_USER}" || -z "${MASTER_DB_PASSWORD}") ]]; then
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

log "Criando databases e owners isolados em ${DB_HOST}:${DB_PORT}"
bootstrap_database "${OS_DATABASE}" "${OS_USERNAME}" "${OS_DB_PASSWORD}"
bootstrap_database "${BILLING_DATABASE}" "${BILLING_USERNAME}" "${BILLING_DB_PASSWORD}"

if [[ "${STORE_IN_SECRETS_MANAGER}" == "true" ]]; then
  upsert_secret "${OS_SECRET_NAME}" "${OS_DATABASE}" "${OS_USERNAME}" "${OS_DB_PASSWORD}"
  upsert_secret "${BILLING_SECRET_NAME}" "${BILLING_DATABASE}" "${BILLING_USERNAME}" "${BILLING_DB_PASSWORD}"
  log "Secrets atualizados: ${OS_SECRET_NAME}, ${BILLING_SECRET_NAME}"
fi

log "Bootstrap concluido sem grants cruzados entre ${OS_USERNAME} e ${BILLING_USERNAME}"
