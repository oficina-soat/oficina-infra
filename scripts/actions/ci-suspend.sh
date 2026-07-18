#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws
require_cmd terraform

log "Validando identidade AWS"
aws sts get-caller-identity >/dev/null

log "Solicitando a parada do RDS enquanto o plano computacional e removido"
"${SCRIPT_DIR}/ci-rds-power.sh" stop

log "Removendo dependencias opcionais da UI sobre o EKS e o VPC Link"
"${SCRIPT_DIR}/ci-ui-workload-lifecycle.sh" suspend

log "Removendo EKS, nodes, NLBs e VPC Link; preservando dados e componentes serverless"
TF_VAR_create_eks=false TERRAFORM_ACTION=apply "${SCRIPT_DIR}/ci-terraform.sh"

"${SCRIPT_DIR}/ci-rds-power.sh" wait-stopped
log "Ambiente lab suspenso"
