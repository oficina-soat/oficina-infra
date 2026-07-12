#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"
DB_IDENTIFIER="${DB_IDENTIFIER:-oficina-postgres-lab}"
DB_SUBNET_GROUP_NAME="${DB_SUBNET_GROUP_NAME:-oficina-postgres-lab-subnet-group}"
DB_PARAMETER_GROUP_NAME="${DB_PARAMETER_GROUP_NAME:-oficina-postgres-lab-pg}"
DB_SECURITY_GROUP_ID="${DB_SECURITY_GROUP_ID:-sg-04530bf6dd8544161}"
RDS_ALLOWED_SECURITY_GROUP_ID="${RDS_ALLOWED_SECURITY_GROUP_ID:-sg-0cafb0f1a30670ece}"
RDS_ALLOWED_SECURITY_GROUP_RULE_ID="${RDS_ALLOWED_SECURITY_GROUP_RULE_ID:-sgr-0c5290e8ce79183ca}"
RDS_EGRESS_RULE_ID="${RDS_EGRESS_RULE_ID:-sgr-0d14bf837d23272ae}"

usage() {
  cat <<EOF
Uso:
  $(basename "$0")

Importa no state do oficina-infra os recursos RDS ja existentes do lab.
Execute depois de renovar as credenciais AWS e inicializar o backend correto.

Variaveis suportadas:
  TERRAFORM_DIR                         Default: terraform/environments/lab
  DB_IDENTIFIER                         Default: oficina-postgres-lab
  DB_SUBNET_GROUP_NAME                  Default: oficina-postgres-lab-subnet-group
  DB_PARAMETER_GROUP_NAME               Default: oficina-postgres-lab-pg
  DB_SECURITY_GROUP_ID                  Default: sg-04530bf6dd8544161
  RDS_ALLOWED_SECURITY_GROUP_ID         Default: sg-0cafb0f1a30670ece
  RDS_ALLOWED_SECURITY_GROUP_RULE_ID    Default: sgr-0c5290e8ce79183ca
  RDS_EGRESS_RULE_ID                    Default: sgr-0d14bf837d23272ae
EOF
}

import_if_missing() {
  local address="$1"
  local id="$2"

  if terraform -chdir="${TERRAFORM_DIR}" state show "${address}" >/dev/null 2>&1; then
    log "Ja importado: ${address}"
    return
  fi

  log "Importando ${address}"
  terraform -chdir="${TERRAFORM_DIR}" import "${address}" "${id}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd terraform

import_if_missing 'module.rds_postgres[0].aws_db_subnet_group.this' "${DB_SUBNET_GROUP_NAME}"
import_if_missing 'module.rds_postgres[0].aws_db_parameter_group.this' "${DB_PARAMETER_GROUP_NAME}"
import_if_missing 'module.rds_postgres[0].aws_security_group.this' "${DB_SECURITY_GROUP_ID}"
import_if_missing 'module.rds_postgres[0].aws_vpc_security_group_ingress_rule.from_security_groups["'"${RDS_ALLOWED_SECURITY_GROUP_ID}"'"]' "${RDS_ALLOWED_SECURITY_GROUP_RULE_ID}"
import_if_missing 'module.rds_postgres[0].aws_vpc_security_group_egress_rule.this' "${RDS_EGRESS_RULE_ID}"
import_if_missing 'module.rds_postgres[0].aws_db_instance.this' "${DB_IDENTIFIER}"
