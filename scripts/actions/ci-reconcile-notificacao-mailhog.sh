#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-lab}"
NOTIFICACAO_LAMBDA_FUNCTION_NAME="${NOTIFICACAO_LAMBDA_FUNCTION_NAME:-oficina-notificacao-lambda-lab}"
NOTIFICACAO_MAILHOG_NLB_NAME="${NOTIFICACAO_MAILHOG_NLB_NAME:-${EKS_CLUSTER_NAME}-mailhog-smtp}"
RECONCILE_NOTIFICACAO_MAILHOG="${RECONCILE_NOTIFICACAO_MAILHOG:-true}"

require_cmd aws
require_cmd jq

if [[ "${RECONCILE_NOTIFICACAO_MAILHOG,,}" != "true" ]]; then
  log "Reconciliacao do MailHog da notificacao-lambda desabilitada"
  exit 0
fi

nlb_dns="$({
  aws --region "${AWS_REGION}" elbv2 describe-load-balancers \
    --names "${NOTIFICACAO_MAILHOG_NLB_NAME}" \
    --query 'LoadBalancers[0].DNSName' \
    --output text
} 2>/dev/null || true)"

if [[ -z "${nlb_dns}" || "${nlb_dns}" == "None" ]]; then
  log "NLB ${NOTIFICACAO_MAILHOG_NLB_NAME} nao encontrado; nenhuma configuracao da Lambda foi alterada"
  exit 0
fi

function_config_file="$(mktemp)"
environment_file="$(mktemp)"
trap 'rm -f "${function_config_file}" "${environment_file}"' EXIT
chmod 600 "${function_config_file}" "${environment_file}"

if ! aws --region "${AWS_REGION}" lambda get-function-configuration \
  --function-name "${NOTIFICACAO_LAMBDA_FUNCTION_NAME}" \
  >"${function_config_file}" 2>/dev/null; then
  log "Lambda ${NOTIFICACAO_LAMBDA_FUNCTION_NAME} nao encontrada; nenhuma configuracao foi alterada"
  exit 0
fi

mailer_mock="$(jq -r '.Environment.Variables.QUARKUS_MAILER_MOCK // "false"' "${function_config_file}")"
current_host="$(jq -r '.Environment.Variables.QUARKUS_MAILER_HOST // empty' "${function_config_file}")"

if [[ "${mailer_mock,,}" == "true" ]]; then
  log "Lambda ${NOTIFICACAO_LAMBDA_FUNCTION_NAME} usa mailer mock explicito; endpoint SMTP preservado"
  exit 0
fi

if [[ "${current_host}" == "${nlb_dns}" ]]; then
  log "Lambda ${NOTIFICACAO_LAMBDA_FUNCTION_NAME} ja usa o NLB atual do MailHog"
  exit 0
fi

if [[ -n "${current_host}" && "${current_host}" != "${NOTIFICACAO_MAILHOG_NLB_NAME}-"*.elb."${AWS_REGION}".amazonaws.com ]]; then
  log "Lambda ${NOTIFICACAO_LAMBDA_FUNCTION_NAME} usa SMTP externo explicito; host ${current_host} preservado"
  exit 0
fi

jq \
  --arg mailer_host "${nlb_dns}" \
  '{
    Variables: ((.Environment.Variables // {}) + {
      QUARKUS_MAILER_HOST: $mailer_host,
      QUARKUS_MAILER_PORT: (.Environment.Variables.QUARKUS_MAILER_PORT // "1025"),
      QUARKUS_MAILER_TLS: (.Environment.Variables.QUARKUS_MAILER_TLS // "false"),
      QUARKUS_MAILER_START_TLS: (.Environment.Variables.QUARKUS_MAILER_START_TLS // "DISABLED")
    })
  }' "${function_config_file}" >"${environment_file}"

aws --region "${AWS_REGION}" lambda wait function-updated \
  --function-name "${NOTIFICACAO_LAMBDA_FUNCTION_NAME}"
aws --region "${AWS_REGION}" lambda update-function-configuration \
  --function-name "${NOTIFICACAO_LAMBDA_FUNCTION_NAME}" \
  --environment "file://${environment_file}" >/dev/null
aws --region "${AWS_REGION}" lambda wait function-updated \
  --function-name "${NOTIFICACAO_LAMBDA_FUNCTION_NAME}"

log "Lambda ${NOTIFICACAO_LAMBDA_FUNCTION_NAME} atualizada para o NLB atual do MailHog"
