#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
DB_IDENTIFIER="${TF_VAR_db_identifier:-${DB_IDENTIFIER:-oficina-postgres-lab}}"
ACTION="${1:-}"

require_cmd aws

db_status() {
  aws --region "${AWS_REGION}" rds describe-db-instances \
    --db-instance-identifier "${DB_IDENTIFIER}" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null
}

start_db() {
  local status

  if ! status="$(db_status)"; then
    log "RDS ${DB_IDENTIFIER} ainda nao existe; o Terraform ira cria-lo"
    return
  fi

  case "${status}" in
    available)
      log "RDS ${DB_IDENTIFIER} ja esta disponivel"
      ;;
    stopped)
      log "Iniciando RDS ${DB_IDENTIFIER}"
      aws --region "${AWS_REGION}" rds start-db-instance \
        --db-instance-identifier "${DB_IDENTIFIER}" >/dev/null
      ;;
    starting)
      log "RDS ${DB_IDENTIFIER} ja esta iniciando"
      ;;
    stopping)
      log "Aguardando RDS ${DB_IDENTIFIER} terminar de parar antes de inicia-lo"
      aws --region "${AWS_REGION}" rds wait db-instance-stopped \
        --db-instance-identifier "${DB_IDENTIFIER}"
      aws --region "${AWS_REGION}" rds start-db-instance \
        --db-instance-identifier "${DB_IDENTIFIER}" >/dev/null
      ;;
    *)
      fail "RDS ${DB_IDENTIFIER} esta no estado ${status}; nao e seguro inicia-lo automaticamente"
      ;;
  esac
}

stop_db() {
  local status

  if ! status="$(db_status)"; then
    log "RDS ${DB_IDENTIFIER} nao existe; nada para parar"
    return
  fi

  case "${status}" in
    available)
      log "Parando RDS ${DB_IDENTIFIER}"
      aws --region "${AWS_REGION}" rds stop-db-instance \
        --db-instance-identifier "${DB_IDENTIFIER}" >/dev/null
      ;;
    stopped)
      log "RDS ${DB_IDENTIFIER} ja esta parado"
      ;;
    stopping)
      log "RDS ${DB_IDENTIFIER} ja esta parando"
      ;;
    starting)
      log "Aguardando RDS ${DB_IDENTIFIER} ficar disponivel antes de para-lo"
      aws --region "${AWS_REGION}" rds wait db-instance-available \
        --db-instance-identifier "${DB_IDENTIFIER}"
      aws --region "${AWS_REGION}" rds stop-db-instance \
        --db-instance-identifier "${DB_IDENTIFIER}" >/dev/null
      ;;
    *)
      fail "RDS ${DB_IDENTIFIER} esta no estado ${status}; nao e seguro para-lo automaticamente"
      ;;
  esac
}

wait_available() {
  if ! db_status >/dev/null; then
    log "RDS ${DB_IDENTIFIER} nao existe; nada para aguardar"
    return
  fi

  log "Aguardando RDS ${DB_IDENTIFIER} ficar disponivel"
  aws --region "${AWS_REGION}" rds wait db-instance-available \
    --db-instance-identifier "${DB_IDENTIFIER}"
}

wait_stopped() {
  if ! db_status >/dev/null; then
    log "RDS ${DB_IDENTIFIER} nao existe; nada para aguardar"
    return
  fi

  log "Aguardando RDS ${DB_IDENTIFIER} parar"
  aws --region "${AWS_REGION}" rds wait db-instance-stopped \
    --db-instance-identifier "${DB_IDENTIFIER}"
}

case "${ACTION}" in
  start) start_db ;;
  stop) stop_db ;;
  wait-available) wait_available ;;
  wait-stopped) wait_stopped ;;
  *) fail "Uso: $(basename "$0") start|stop|wait-available|wait-stopped" ;;
esac
