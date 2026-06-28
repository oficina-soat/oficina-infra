#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd terraform
require_cmd kubectl

terraform fmt -check -recursive "${REPO_ROOT}/terraform"
TERRAFORM_ACTION=validate "${SCRIPT_DIR}/ci-terraform.sh"
kubectl kustomize "${REPO_ROOT}/k8s/overlays/lab" >/tmp/oficina-infra-lab-rendered.yaml
find "${REPO_ROOT}/scripts" -type f -name '*.sh' -print0 | xargs -0 bash -n
