#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd terraform
require_cmd kubectl
require_cmd yq
require_cmd python3

validate_yaml_files() {
  local yaml_files=()

  while IFS= read -r -d '' file; do
    yaml_files+=("${file}")
  done < <(
    find "${REPO_ROOT}" \
      -path "${REPO_ROOT}/.git" -prune -o \
      -type f \( -name '*.yaml' -o -name '*.yml' \) -print0
  )

  if [[ ${#yaml_files[@]} -gt 0 ]]; then
    yq e '.' "${yaml_files[@]}" >/dev/null
  fi
}

terraform fmt -check -recursive "${REPO_ROOT}/terraform"
TERRAFORM_ACTION=validate "${SCRIPT_DIR}/ci-terraform.sh"
validate_yaml_files
kubectl kustomize "${REPO_ROOT}/k8s/overlays/lab" >/tmp/oficina-infra-lab-rendered.yaml
if [[ -n "${MICROSERVICE_REPOSITORIES_ROOT:-}" ]]; then
  for service in oficina-os-service oficina-billing-service oficina-execution-service; do
    kubectl kustomize "${MICROSERVICE_REPOSITORIES_ROOT}/${service}/k8s/base" \
      >"/tmp/${service}-rendered.yaml"
  done
fi
find "${REPO_ROOT}/scripts" -type f -name '*.sh' -print0 | xargs -0 bash -n
python3 -m unittest discover -s "${REPO_ROOT}/tests" -p 'test_*.py'
