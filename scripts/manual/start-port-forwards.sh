#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-lab}"
UPDATE_KUBECONFIG="${UPDATE_KUBECONFIG:-auto}"
K8S_NAMESPACE="${K8S_NAMESPACE:-default}"
MICROSERVICE_NAMES="${MICROSERVICE_NAMES:-oficina-os-service oficina-billing-service oficina-execution-service}"
FORWARD_MICROSERVICES="${FORWARD_MICROSERVICES:-true}"
FORWARD_MAILHOG="${FORWARD_MAILHOG:-true}"
VERIFY_SWAGGER="${VERIFY_SWAGGER:-true}"

OFICINA_OS_LOCAL_PORT="${OFICINA_OS_LOCAL_PORT:-8081}"
OFICINA_BILLING_LOCAL_PORT="${OFICINA_BILLING_LOCAL_PORT:-8082}"
OFICINA_EXECUTION_LOCAL_PORT="${OFICINA_EXECUTION_LOCAL_PORT:-8083}"

PORT_FORWARD_SUMMARY=""

declare -A SERVICE_LOCAL_PORTS=(
	["oficina-os-service"]="${OFICINA_OS_LOCAL_PORT}"
	["oficina-billing-service"]="${OFICINA_BILLING_LOCAL_PORT}"
	["oficina-execution-service"]="${OFICINA_EXECUTION_LOCAL_PORT}"
)

usage() {
	cat <<EOF
Uso:
  $(basename "$0")

Variaveis suportadas:
  UPDATE_KUBECONFIG             auto|true|false. Default: auto
  EKS_CLUSTER_NAME              Nome do cluster EKS. Default: eks-lab
  AWS_REGION                    Regiao AWS. Default: us-east-1
  K8S_NAMESPACE                 Namespace dos microsservicos. Default: default
  MICROSERVICE_NAMES            Servicos separados por espaco ou virgula. Default: todos
  FORWARD_MICROSERVICES         true|false. Default: true
  FORWARD_MAILHOG               true|false. Default: true
  VERIFY_SWAGGER                true|false. Valida /q/openapi e /q/swagger-ui. Default: true
  OFICINA_OS_LOCAL_PORT         Porta local do oficina-os-service. Default: 8081
  OFICINA_BILLING_LOCAL_PORT    Porta local do oficina-billing-service. Default: 8082
  OFICINA_EXECUTION_LOCAL_PORT  Porta local do oficina-execution-service. Default: 8083
EOF
}

current_kube_server() {
	kubectl config view --minify --output=jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true
}

eks_cluster_endpoint() {
	aws eks describe-cluster \
		--region "${AWS_REGION}" \
		--name "${EKS_CLUSTER_NAME}" \
		--query 'cluster.endpoint' \
		--output text 2>/dev/null || true
}

update_kubeconfig() {
	log "Atualizando kubeconfig do cluster ${EKS_CLUSTER_NAME}"
	aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"
}

ensure_kubeconfig() {
	case "${UPDATE_KUBECONFIG}" in
	true)
		require_cmd aws
		require_non_empty "${EKS_CLUSTER_NAME}" "EKS_CLUSTER_NAME"
		update_kubeconfig
		;;
	auto)
		if ! command -v aws >/dev/null 2>&1; then
			log "AWS CLI nao encontrado; usando kubeconfig atual."
			return 0
		fi

		require_non_empty "${EKS_CLUSTER_NAME}" "EKS_CLUSTER_NAME"

		local current_server expected_endpoint
		current_server="$(current_kube_server)"
		expected_endpoint="$(eks_cluster_endpoint)"

		if [[ -z "${expected_endpoint}" || "${expected_endpoint}" == "None" ]]; then
			log "Nao foi possivel consultar o endpoint do cluster ${EKS_CLUSTER_NAME}; usando kubeconfig atual."
			return 0
		fi

		if [[ "${current_server}" != "${expected_endpoint}" ]]; then
			log "Kubeconfig aponta para endpoint diferente do cluster ativo; atualizando."
			update_kubeconfig
		fi
		;;
	false) ;;
	*)
		fail "UPDATE_KUBECONFIG deve ser auto, true ou false"
		;;
	esac
}

ensure_cluster_access() {
	if kubectl get namespace "${K8S_NAMESPACE}" >/dev/null 2>&1; then
		return 0
	fi

	fail "Nao foi possivel acessar o namespace ${K8S_NAMESPACE}. Tente UPDATE_KUBECONFIG=true EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME} AWS_REGION=${AWS_REGION}."
}

normalize_services() {
	tr ',' ' ' <<<"${MICROSERVICE_NAMES}" | xargs
}

service_selected() {
	local service_name="$1"
	local selected

	for selected in $(normalize_services); do
		if [[ "${selected}" == "${service_name}" ]]; then
			return 0
		fi
	done

	return 1
}

service_exists() {
	local namespace="$1"
	local service_name="$2"

	kubectl get svc "${service_name}" --namespace "${namespace}" >/dev/null 2>&1
}

local_port_open() {
	local port="$1"

	bash -c ":</dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1
}

port_forward_ports_open() {
	local ports="$1"
	local mapping local_port

	for mapping in ${ports}; do
		local_port="${mapping%%:*}"
		if ! local_port_open "${local_port}"; then
			return 1
		fi
	done

	return 0
}

pid_is_port_forward() {
	local pid="$1"
	local service_name="$2"
	local command_line

	command_line="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
	[[ "${command_line}" == *"kubectl"* && "${command_line}" == *"port-forward"* && "${command_line}" == *"svc/${service_name}"* ]]
}

wait_for_port_forward() {
	local pid="$1"
	local ports="$2"
	local log_file="$3"
	local _attempt

	for _attempt in {1..10}; do
		if ! kill -0 "${pid}" >/dev/null 2>&1; then
			echo "Falha ao iniciar port-forward. Ultimas linhas de ${log_file}:" >&2
			tail -40 "${log_file}" >&2 || true
			return 1
		fi

		if port_forward_ports_open "${ports}"; then
			return 0
		fi

		sleep 1
	done

	echo "Port-forward iniciou, mas as portas locais nao ficaram acessiveis: ${ports}. Veja ${log_file}" >&2
	tail -40 "${log_file}" >&2 || true
	return 1
}

verify_url() {
	local label="$1"
	local url="$2"

	if ! curl --fail --silent --show-error --location --max-time 10 "${url}" >/dev/null; then
		fail "Swagger indisponivel em ${label}: ${url}"
	fi
}

verify_swagger() {
	local service_name="$1"
	local local_port="$2"
	local base_url="http://localhost:${local_port}"

	if [[ "${VERIFY_SWAGGER}" != "true" ]]; then
		return 0
	fi

	verify_url "${service_name} OpenAPI" "${base_url}/q/openapi"
	verify_url "${service_name} Swagger UI" "${base_url}/q/swagger-ui"
	log "Swagger validado para ${service_name}: ${base_url}/q/swagger-ui"
}

append_summary() {
	local line="$1"

	PORT_FORWARD_SUMMARY+="${line}"$'\n'
}

start_port_forward() {
	local namespace="$1"
	local service_name="$2"
	local ports="$3"
	local slug="$4"
	local summary_line="$5"
	local pf_dir="${REPO_ROOT}/.tmp/port-forward"
	local log_file="${pf_dir}/${slug}.log"
	local pid_file="${pf_dir}/${slug}.pid"
	local -a port_args=()

	read -r -a port_args <<<"${ports}"

	if ! service_exists "${namespace}" "${service_name}"; then
		log "Port-forward ignorado: service ${namespace}/${service_name} nao existe"
		return 0
	fi

	mkdir -p "${pf_dir}"

	if [[ -f "${pid_file}" ]]; then
		local existing_pid
		existing_pid="$(cat "${pid_file}")"
		if kill -0 "${existing_pid}" >/dev/null 2>&1 && pid_is_port_forward "${existing_pid}" "${service_name}" && port_forward_ports_open "${ports}"; then
			log "Port-forward ja ativo para ${namespace}/${service_name} (pid ${existing_pid})"
			append_summary "${summary_line}"
			return 0
		fi
		rm -f "${pid_file}"
	fi

	log "Iniciando port-forward para ${namespace}/${service_name} em ${ports}"
	: >"${log_file}"
	if command -v setsid >/dev/null 2>&1; then
		setsid kubectl --namespace "${namespace}" port-forward "svc/${service_name}" "${port_args[@]}" >"${log_file}" 2>&1 &
	else
		nohup kubectl --namespace "${namespace}" port-forward "svc/${service_name}" "${port_args[@]}" >"${log_file}" 2>&1 &
	fi
	local pf_pid=$!
	echo "${pf_pid}" >"${pid_file}"

	if ! wait_for_port_forward "${pf_pid}" "${ports}" "${log_file}"; then
		rm -f "${pid_file}"
		exit 1
	fi

	append_summary "${summary_line}"
}

start_microservice_forward() {
	local service_name="$1"
	local local_port="${SERVICE_LOCAL_PORTS[${service_name}]}"
	local base_url="http://localhost:${local_port}"

	start_port_forward \
		"${K8S_NAMESPACE}" \
		"${service_name}" \
		"${local_port}:8080" \
		"${service_name}" \
		"${service_name}: ${base_url} | Swagger: ${base_url}/q/swagger-ui | OpenAPI: ${base_url}/q/openapi"

	verify_swagger "${service_name}" "${local_port}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

require_cmd kubectl
if [[ "${VERIFY_SWAGGER}" == "true" ]]; then
	require_cmd curl
fi

ensure_kubeconfig
ensure_cluster_access

log "Configuracao efetiva"
cat <<EOF
UPDATE_KUBECONFIG=${UPDATE_KUBECONFIG}
AWS_REGION=${AWS_REGION}
EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME}
K8S_NAMESPACE=${K8S_NAMESPACE}
MICROSERVICE_NAMES=$(normalize_services)
FORWARD_MICROSERVICES=${FORWARD_MICROSERVICES}
FORWARD_MAILHOG=${FORWARD_MAILHOG}
VERIFY_SWAGGER=${VERIFY_SWAGGER}
OFICINA_OS_LOCAL_PORT=${OFICINA_OS_LOCAL_PORT}
OFICINA_BILLING_LOCAL_PORT=${OFICINA_BILLING_LOCAL_PORT}
OFICINA_EXECUTION_LOCAL_PORT=${OFICINA_EXECUTION_LOCAL_PORT}
EOF

if [[ "${FORWARD_MICROSERVICES}" == "true" ]]; then
	for service_name in oficina-os-service oficina-billing-service oficina-execution-service; do
		if service_selected "${service_name}"; then
			start_microservice_forward "${service_name}"
		fi
	done
fi

if [[ "${FORWARD_MAILHOG}" == "true" ]]; then
	start_port_forward \
		"default" \
		"mailhog" \
		"8025:8025 1025:1025" \
		"mailhog" \
		"MailHog UI: http://localhost:8025 | SMTP: localhost:1025"
fi

log "Encaminhamentos ativos"
cat <<EOF
${PORT_FORWARD_SUMMARY}Logs e PIDs: ${REPO_ROOT}/.tmp/port-forward
EOF
