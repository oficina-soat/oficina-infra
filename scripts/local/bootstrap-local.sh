#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

COMPOSE_FILE="${COMPOSE_FILE:-${REPO_ROOT}/compose.local.yml}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-local}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-local}"
DYNAMODB_ENDPOINT_URL="${DYNAMODB_ENDPOINT_URL:-http://dynamodb:8000}"
LOCALSTACK_ENDPOINT_URL="${LOCALSTACK_ENDPOINT_URL:-http://localstack:4566}"
TABLE_PREFIX="${OFICINA_DYNAMODB_TABLE_PREFIX:-oficina-execution-lab}"

compose() {
  docker compose -f "${COMPOSE_FILE}" "$@"
}

aws_localstack() {
  compose run --rm \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_REGION}" \
    aws-cli --endpoint-url "${LOCALSTACK_ENDPOINT_URL}" "$@"
}

aws_dynamodb() {
  compose run --rm \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    -e AWS_DEFAULT_REGION="${AWS_REGION}" \
    aws-cli --endpoint-url "${DYNAMODB_ENDPOINT_URL}" "$@"
}

physical_name() {
  local logical_name="$1"

  printf '%s' "${logical_name//./-}"
}

create_table_if_missing() {
  local table_name="$1"

  if aws_dynamodb dynamodb describe-table --table-name "${table_name}" >/dev/null 2>&1; then
    log "DynamoDB table ja existe: ${table_name}"
    return
  fi

  log "Criando DynamoDB table: ${table_name}"
  aws_dynamodb dynamodb create-table \
    --table-name "${table_name}" \
    --attribute-definitions \
      AttributeName=PK,AttributeType=S \
      AttributeName=SK,AttributeType=S \
      AttributeName=GSI1PK,AttributeType=S \
      AttributeName=GSI1SK,AttributeType=S \
      AttributeName=GSI2PK,AttributeType=S \
      AttributeName=GSI2SK,AttributeType=S \
    --key-schema \
      AttributeName=PK,KeyType=HASH \
      AttributeName=SK,KeyType=RANGE \
    --global-secondary-indexes \
      "IndexName=GSI1,KeySchema=[{AttributeName=GSI1PK,KeyType=HASH},{AttributeName=GSI1SK,KeyType=RANGE}],Projection={ProjectionType=ALL}" \
      "IndexName=GSI2,KeySchema=[{AttributeName=GSI2PK,KeyType=HASH},{AttributeName=GSI2SK,KeyType=RANGE}],Projection={ProjectionType=ALL}" \
    --billing-mode PAY_PER_REQUEST >/dev/null
}

create_messaging_route() {
  local event_type="$1"
  local topic="$2"
  local producer="$3"
  shift 3
  local consumers=("$@")
  local topic_name
  topic_name="$(physical_name "${topic}")"

  log "Criando topico SNS local: ${topic} -> ${topic_name} (${event_type}, producer ${producer})"
  local topic_arn
  topic_arn="$(aws_localstack sns create-topic --name "${topic_name}" --query TopicArn --output text)"

  local dlq_name
  dlq_name="$(physical_name "${topic}.dlq")"
  local dlq_url
  dlq_url="$(aws_localstack sqs create-queue --queue-name "${dlq_name}" --query QueueUrl --output text)"
  local dlq_arn
  dlq_arn="$(aws_localstack sqs get-queue-attributes \
    --queue-url "${dlq_url}" \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' \
    --output text)"

  for consumer in "${consumers[@]}"; do
    local queue_name
    local queue_url
    local queue_arn
    local redrive_policy
    local queue_attributes

    queue_name="$(physical_name "${topic}.${consumer}")"
    redrive_policy="$(printf '{"deadLetterTargetArn":"%s","maxReceiveCount":"5"}' "${dlq_arn}")"
    queue_attributes="$(printf '{"RedrivePolicy":"%s"}' "${redrive_policy//\"/\\\"}")"
    queue_url="$(aws_localstack sqs create-queue \
      --queue-name "${queue_name}" \
      --attributes "${queue_attributes}" \
      --query QueueUrl \
      --output text)"
    queue_arn="$(aws_localstack sqs get-queue-attributes \
      --queue-url "${queue_url}" \
      --attribute-names QueueArn \
      --query 'Attributes.QueueArn' \
      --output text)"

    aws_localstack sns subscribe \
      --topic-arn "${topic_arn}" \
      --protocol sqs \
      --notification-endpoint "${queue_arn}" >/dev/null
  done
}

bootstrap_dynamodb() {
  log "Criando tabelas DynamoDB locais"
  create_table_if_missing "${TABLE_PREFIX}-catalogo"
  create_table_if_missing "${TABLE_PREFIX}-estoque"
  create_table_if_missing "${TABLE_PREFIX}-execucoes"
  create_table_if_missing "${TABLE_PREFIX}-outbox"
  create_table_if_missing "${TABLE_PREFIX}-idempotencia"
}

bootstrap_messaging() {
  log "Criando SNS/SQS locais"
  create_messaging_route ordemDeServicoCriada oficina.os.ordem-de-servico-criada oficina-os-service oficina-billing-service oficina-execution-service
  create_messaging_route diagnosticoIniciado oficina.execution.diagnostico-iniciado oficina-execution-service oficina-os-service
  create_messaging_route pecaIncluidaNaOrdemDeServico oficina.os.peca-incluida-na-ordem-de-servico oficina-os-service oficina-billing-service oficina-execution-service
  create_messaging_route servicoIncluidoNaOrdemDeServico oficina.os.servico-incluido-na-ordem-de-servico oficina-os-service oficina-billing-service oficina-execution-service
  create_messaging_route diagnosticoFinalizado oficina.execution.diagnostico-finalizado oficina-execution-service oficina-os-service oficina-billing-service
  create_messaging_route orcamentoGerado oficina.billing.orcamento-gerado oficina-billing-service oficina-os-service
  create_messaging_route orcamentoAprovado oficina.billing.orcamento-aprovado oficina-billing-service oficina-os-service oficina-execution-service
  create_messaging_route orcamentoRecusado oficina.billing.orcamento-recusado oficina-billing-service oficina-os-service
  create_messaging_route execucaoIniciada oficina.execution.execucao-iniciada oficina-execution-service oficina-os-service
  create_messaging_route execucaoFinalizada oficina.execution.execucao-finalizada oficina-execution-service oficina-os-service oficina-billing-service
  create_messaging_route ordemDeServicoFinalizada oficina.os.ordem-de-servico-finalizada oficina-os-service oficina-billing-service oficina-execution-service
  create_messaging_route ordemDeServicoEntregue oficina.os.ordem-de-servico-entregue oficina-os-service oficina-billing-service
  create_messaging_route pagamentoSolicitado oficina.billing.pagamento-solicitado oficina-billing-service oficina-os-service
  create_messaging_route pagamentoConfirmado oficina.billing.pagamento-confirmado oficina-billing-service oficina-os-service
  create_messaging_route pagamentoRecusado oficina.billing.pagamento-recusado oficina-billing-service oficina-os-service
  create_messaging_route estoqueAcrescentado oficina.execution.estoque-acrescentado oficina-execution-service oficina-billing-service
  create_messaging_route estoqueBaixado oficina.execution.estoque-baixado oficina-execution-service oficina-billing-service
  create_messaging_route sagaCompensada oficina.saga.saga-compensada oficina-os-service oficina-billing-service oficina-execution-service
  create_messaging_route sagaFinalizadaComSucesso oficina.saga.saga-finalizada-com-sucesso oficina-os-service oficina-billing-service oficina-execution-service
}

main() {
  require_cmd docker

  log "Subindo dependencias locais"
  compose up -d postgres dynamodb localstack

  log "Aguardando servicos locais ficarem saudaveis"
  compose ps

  bootstrap_dynamodb
  bootstrap_messaging

  log "Bootstrap local concluido"
}

main "$@"
