#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

OFICINA_API_BASE_URL="${OFICINA_API_BASE_URL:-}"
OFICINA_AUTH_TOKEN="${OFICINA_AUTH_TOKEN:-}"
RECONCILE_RECEIVED="false"
PAGE_SIZE=100
TMP_DIR=""

usage() {
	cat <<EOF
Uso:
  OFICINA_API_BASE_URL=https://api.example/api/v1 \
  OFICINA_AUTH_TOKEN=<jwt> $(basename "$0") [--reconcile-received]

Opcoes:
  --reconcile-received  Cria de forma idempotente a execucao ausente somente para OS em RECEBIDA.
  --help                Exibe esta ajuda.

O modo padrao e somente leitura. O script retorna 2 enquanto houver OS operacional
sem execucao associada e nunca imprime o token de autenticacao.
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
	require_non_empty "${OFICINA_API_BASE_URL}" "OFICINA_API_BASE_URL"
	require_non_empty "${OFICINA_AUTH_TOKEN}" "OFICINA_AUTH_TOKEN"
	OFICINA_API_BASE_URL="$(normalize_base_url "${OFICINA_API_BASE_URL}")"

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

main "$@"
