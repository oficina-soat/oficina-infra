#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd terraform
require_cmd kubectl
require_cmd yq

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
kubectl kustomize "${REPO_ROOT}/k8s/base/microservices" >/tmp/oficina-infra-microservices-rendered.yaml
kubectl kustomize "${REPO_ROOT}/k8s/overlays/lab" >/tmp/oficina-infra-lab-rendered.yaml
find "${REPO_ROOT}/scripts" -type f -name '*.sh' -print0 | xargs -0 bash -n
