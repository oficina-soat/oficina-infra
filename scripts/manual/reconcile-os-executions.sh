#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

OFICINA_API_BASE_URL="${OFICINA_API_BASE_URL:-}"
OFICINA_AUTH_TOKEN="${OFICINA_AUTH_TOKEN:-}"
OFICINA_AWS_REGION="${OFICINA_AWS_REGION:-us-east-1}"
OFICINA_EXECUTION_TABLE_NAME="${OFICINA_EXECUTION_TABLE_NAME:-oficina-execution-lab-execucoes}"
RECONCILE_RECEIVED="false"
BACKFILL_HISTORICAL="false"
PAGE_SIZE=100
TMP_DIR=""

usage() {
	cat <<EOF
Uso:
  OFICINA_API_BASE_URL=https://api.example/api/v1 \
  OFICINA_AUTH_TOKEN=<jwt> $(basename "$0") [--reconcile-received] [--backfill-historical]

Opcoes:
  --reconcile-received  Cria de forma idempotente a execucao ausente somente para OS em RECEBIDA.
  --backfill-historical Cria no DynamoDB do lab uma execucao compativel com o estado atual de OS historica.
  --help                Exibe esta ajuda.

O modo padrao e somente leitura. O script retorna 2 enquanto houver OS operacional
sem execucao associada e nunca imprime o token de autenticacao. O backfill historico
nao publica eventos nem altera a OS e exige acesso AWS a tabela canonica do lab.
EOF
}

cleanup() {
	if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
		rm -rf -- "${TMP_DIR}"
	fi
}

normalize_base_url() {
	local value="$1"

	while [[ "${value}" == */ ]]; do
		value="${value%/}"
	done

	printf '%s' "${value}"
}

api_request() {
	local method="$1"
	local path="$2"
	local output_file="$3"
	local body_file="${4:-}"
	local idempotency_key="${5:-}"
	local -a request=(
		--silent
		--show-error
		--connect-timeout 10
		--max-time 30
		--request "${method}"
		--output "${output_file}"
		--write-out '%{http_code}'
		--header "Authorization: Bearer ${OFICINA_AUTH_TOKEN}"
		--header 'Accept: application/json'
		--header 'X-Correlation-Id: os-execution-reconciliation'
	)

	if [[ -n "${body_file}" ]]; then
		request+=(--header 'Content-Type: application/json' --data-binary "@${body_file}")
	fi

	if [[ -n "${idempotency_key}" ]]; then
		request+=(--header "X-Idempotency-Key: ${idempotency_key}")
	fi

	curl "${request[@]}" "${OFICINA_API_BASE_URL}${path}"
}

require_success() {
	local status="$1"
	local operation="$2"

	if [[ "${status}" != 2* ]]; then
		fail "${operation} falhou com HTTP ${status}"
	fi
}

fetch_orders() {
	local output_file="$1"
	local page=0
	local total_pages=1
	local page_file="${TMP_DIR}/orders-page.json"
	local merged_file="${TMP_DIR}/orders-merged.json"
	local status

	printf '[]\n' >"${output_file}"

	while ((page < total_pages)); do
		status="$(api_request GET "/ordens-servico?page=${page}&size=${PAGE_SIZE}" "${page_file}")"
		require_success "${status}" "consulta da pagina ${page} de OS"
		jq -e '
			type == "object"
			and (.items | type == "array")
			and (.totalPages | type == "number")
		' "${page_file}" >/dev/null || fail "resposta invalida na consulta de OS"

		jq -s '.[0] + .[1].items' "${output_file}" "${page_file}" >"${merged_file}"
		mv "${merged_file}" "${output_file}"
		total_pages="$(jq -r '.totalPages' "${page_file}")"
		page=$((page + 1))
	done
}

fetch_executions() {
	local output_file="$1"
	local status

	status="$(api_request GET '/execucoes' "${output_file}")"
	require_success "${status}" "consulta de execucoes"
	jq -e 'type == "array"' "${output_file}" >/dev/null || fail "resposta invalida na consulta de execucoes"
}

find_orphans() {
	local orders_file="$1"
	local executions_file="$2"
	local output_file="$3"

	jq -n \
		--slurpfile orders "${orders_file}" \
		--slurpfile executions "${executions_file}" '
		[
			$orders[0][]
			| select(.estado != "ENTREGUE")
			| select(
				.ordemServicoId as $orderId
				| ($executions[0] | any(.ordemServicoId == $orderId) | not)
			)
			| {ordemServicoId, estado}
		]
		| sort_by(.estado, .ordemServicoId)
	' >"${output_file}"
}

reconcile_received_order() {
	local order_id="$1"
	local response_file="${TMP_DIR}/reconcile-${order_id}.json"
	local lookup_file="${TMP_DIR}/lookup-${order_id}.json"
	local request_file="${TMP_DIR}/request-${order_id}.json"
	local idempotency_key="reconcile-execution-${order_id}"
	local status lookup_status execution_id

	jq -n --arg orderId "${order_id}" '{ordemServicoId: $orderId}' >"${request_file}"
	status="$(api_request POST '/execucoes' "${response_file}" "${request_file}" "${idempotency_key}")"

	if [[ "${status}" == "201" ]]; then
		execution_id="$(jq -r '.execucaoId // empty' "${response_file}")"
		require_non_empty "${execution_id}" "execucaoId retornado para a OS ${order_id}"
		log "OS ${order_id} reconciliada com a execucao ${execution_id}."
		return
	fi

	if [[ "${status}" == "409" ]]; then
		lookup_status="$(api_request GET "/ordens-servico/${order_id}/execucao" "${lookup_file}")"
		if [[ "${lookup_status}" == "200" ]]; then
			execution_id="$(jq -r '.execucaoId // empty' "${lookup_file}")"
			require_non_empty "${execution_id}" "execucaoId consultado para a OS ${order_id}"
			log "OS ${order_id} ja estava associada a execucao ${execution_id}; conflito tratado de forma idempotente."
			return
		fi
	fi

	fail "reconciliacao da OS ${order_id} falhou com HTTP ${status}"
}

deterministic_uuid() {
	local namespace="$1"
	local value="$2"
	local digest

	digest="$(printf '%s:%s' "${namespace}" "${value}" | sha256sum | cut -c1-32)"
	printf '%s-%s-5%s-a%s-%s' \
		"${digest:0:8}" \
		"${digest:8:4}" \
		"${digest:13:3}" \
		"${digest:17:3}" \
		"${digest:20:12}"
}

execution_status_for_order_state() {
	case "$1" in
	EM_DIAGNOSTICO)
		printf 'EM_DIAGNOSTICO'
		;;
	AGUARDANDO_APROVACAO)
		printf 'DIAGNOSTICO_CONCLUIDO'
		;;
	EM_EXECUCAO)
		printf 'EM_REPARO'
		;;
	FINALIZADA)
		printf 'REPARO_CONCLUIDO'
		;;
	*)
		return 1
		;;
	esac
}

is_queue_status() {
	[[ "$1" == "CRIADA" || "$1" == "EM_DIAGNOSTICO" || "$1" == "EM_REPARO" ]]
}

historical_backfill_transaction() {
	local order_id="$1"
	local execution_status="$2"
	local transaction_file="$3"
	local execution_id history_id now metadata_key history_key priority_created_at

	execution_id="$(deterministic_uuid 'oficina-execution-reconciliation' "${order_id}")"
	history_id="$(deterministic_uuid 'oficina-execution-reconciliation-history' "${order_id}")"
	now="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"
	metadata_key="EXECUCAO#${execution_id}"
	history_key="HISTORICO#${now}#${history_id}"
	priority_created_at="0000000100#${now}#${execution_id}"

	jq -n \
		--arg tableName "${OFICINA_EXECUTION_TABLE_NAME}" \
		--arg metadataKey "${metadata_key}" \
		--arg historyKey "${history_key}" \
		--arg executionId "${execution_id}" \
		--arg orderId "${order_id}" \
		--arg status "${execution_status}" \
		--arg now "${now}" \
		--arg historyId "${history_id}" \
		--arg priorityCreatedAt "${priority_created_at}" \
		--arg correlationId "os-execution-reconciliation-backfill" \
		--arg description "Backfill operacional de execucao historica sem eventos retroativos" \
		--argjson queueStatus "$(if is_queue_status "${execution_status}"; then jq -n --arg value "${execution_status}" '{S: $value}'; else printf 'null'; fi)" '
		def s($value): {S: $value};
		def n($value): {N: ($value | tostring)};
		def conditional_put($table; $item): {
			Put: {
				TableName: $table,
				Item: $item,
				ConditionExpression: "attribute_not_exists(PK) AND attribute_not_exists(SK)"
			}
		};
		[
			conditional_put($tableName; ({
				PK: s($metadataKey),
				SK: s("METADATA"),
				entityType: s("EXECUCAO"),
				execucaoId: s($executionId),
				ordemServicoId: s($orderId),
				status: s($status),
				prioridade: n(100),
				createdAt: s($now),
				updatedAt: s($now),
				correlationId: s($correlationId)
			} + if $queueStatus == null then {} else {
				filaStatus: $queueStatus,
				prioridadeCriadoEm: s($priorityCreatedAt)
			} end)),
			conditional_put($tableName; {
				PK: s($metadataKey),
				SK: s($historyKey),
				entityType: s("EXECUCAO_HISTORICO"),
				historicoId: s($historyId),
				execucaoId: s($executionId),
				ordemServicoId: s($orderId),
				statusNovo: s($status),
				descricao: s($description),
				createdAt: s($now),
				correlationId: s($correlationId)
			})
		]
	' >"${transaction_file}"
}

wait_for_execution_association() {
	local order_id="$1"
	local output_file="${TMP_DIR}/lookup-${order_id}.json"
	local attempt status execution_id

	for ((attempt = 1; attempt <= 5; attempt++)); do
		status="$(api_request GET "/ordens-servico/${order_id}/execucao" "${output_file}")"
		if [[ "${status}" == "200" ]]; then
			execution_id="$(jq -r '.execucaoId // empty' "${output_file}")"
			require_non_empty "${execution_id}" "execucaoId consultado para a OS ${order_id}"
			log "OS ${order_id} associada a execucao historica ${execution_id}."
			return
		fi
		sleep 1
	done

	fail "backfill da OS ${order_id} nao ficou visivel pela API apos cinco tentativas"
}

backfill_historical_order() {
	local order_id="$1"
	local order_state="$2"
	local execution_status transaction_file error_file

	if ! execution_status="$(execution_status_for_order_state "${order_state}")"; then
		fail "estado ${order_state} nao possui mapeamento aprovado para backfill historico"
	fi

	transaction_file="${TMP_DIR}/backfill-${order_id}.json"
	error_file="${TMP_DIR}/backfill-${order_id}.err"
	historical_backfill_transaction "${order_id}" "${execution_status}" "${transaction_file}"

	if aws dynamodb transact-write-items \
		--region "${OFICINA_AWS_REGION}" \
		--transact-items "file://${transaction_file}" 2>"${error_file}"; then
		log "Backfill da OS ${order_id}: ${order_state} -> ${execution_status}; nenhum evento foi publicado."
		wait_for_execution_association "${order_id}"
		return
	fi

	if grep -q 'TransactionCanceledException' "${error_file}"; then
		log "Backfill da OS ${order_id} encontrou gravacao concorrente; verificando associacao atual."
		wait_for_execution_association "${order_id}"
		return
	fi

	cat "${error_file}" >&2
	fail "backfill historico da OS ${order_id} falhou"
}

report_orphans() {
	local orphans_file="$1"
	local count

	count="$(jq 'length' "${orphans_file}")"
	if [[ "${count}" == "0" ]]; then
		log "Nenhuma OS operacional sem execucao associada."
		return
	fi

	log "Detectadas ${count} OS operacionais sem execucao associada:"
	jq -r '.[] | "- \(.ordemServicoId) [\(.estado)]"' "${orphans_file}"
}

main() {
	local orders_file executions_file orphans_file remaining_file
	local order_id state remaining_count

	while (($# > 0)); do
		case "$1" in
		--reconcile-received)
			RECONCILE_RECEIVED="true"
			;;
		--backfill-historical)
			BACKFILL_HISTORICAL="true"
			;;
		--help | -h)
			usage
			exit 0
			;;
		*)
			usage >&2
			fail "opcao desconhecida: $1"
			;;
		esac
		shift
	done

	require_cmd curl
	require_cmd jq
	require_cmd sha256sum
	require_non_empty "${OFICINA_API_BASE_URL}" "OFICINA_API_BASE_URL"
	require_non_empty "${OFICINA_AUTH_TOKEN}" "OFICINA_AUTH_TOKEN"
	OFICINA_API_BASE_URL="$(normalize_base_url "${OFICINA_API_BASE_URL}")"
	if [[ "${BACKFILL_HISTORICAL}" == "true" ]]; then
		require_cmd aws
		if [[ "${OFICINA_EXECUTION_TABLE_NAME}" != "oficina-execution-lab-execucoes" ]]; then
			fail "backfill historico permitido somente em oficina-execution-lab-execucoes"
		fi
	fi

	TMP_DIR="$(mktemp -d)"
	trap cleanup EXIT
	orders_file="${TMP_DIR}/orders.json"
	executions_file="${TMP_DIR}/executions.json"
	orphans_file="${TMP_DIR}/orphans.json"
	remaining_file="${TMP_DIR}/remaining.json"

	fetch_orders "${orders_file}"
	fetch_executions "${executions_file}"
	find_orphans "${orders_file}" "${executions_file}" "${orphans_file}"
	report_orphans "${orphans_file}"

	if [[ "${RECONCILE_RECEIVED}" == "true" ]]; then
		while IFS=$'\t' read -r order_id state; do
			if [[ "${state}" == "RECEBIDA" ]]; then
				reconcile_received_order "${order_id}"
			else
				log "OS ${order_id} em ${state} exige decisao operacional; nenhum estado foi alterado."
			fi
		done < <(jq -r '.[] | [.ordemServicoId, .estado] | @tsv' "${orphans_file}")

	fi

	if [[ "${BACKFILL_HISTORICAL}" == "true" ]]; then
		while IFS=$'\t' read -r order_id state; do
			if execution_status_for_order_state "${state}" >/dev/null; then
				backfill_historical_order "${order_id}" "${state}"
			else
				log "OS ${order_id} em ${state} nao pertence ao backfill historico aprovado."
			fi
		done < <(jq -r '.[] | [.ordemServicoId, .estado] | @tsv' "${orphans_file}")
	fi

	if [[ "${RECONCILE_RECEIVED}" == "true" || "${BACKFILL_HISTORICAL}" == "true" ]]; then
		fetch_executions "${executions_file}"
		find_orphans "${orders_file}" "${executions_file}" "${remaining_file}"
	else
		cp "${orphans_file}" "${remaining_file}"
	fi

	remaining_count="$(jq 'length' "${remaining_file}")"
	if [[ "${remaining_count}" != "0" ]]; then
		log "Permanecem ${remaining_count} divergencias; encerrando com codigo 2 para integracao com monitoramento."
		exit 2
	fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
