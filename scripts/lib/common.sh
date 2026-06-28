#!/usr/bin/env bash

log() {
  printf '[oficina-infra] %s\n' "$*"
}

fail() {
  printf '[oficina-infra] erro: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "comando obrigatorio nao encontrado: $1"
}

require_non_empty() {
  local value="$1"
  local name="$2"

  [[ -n "${value}" ]] || fail "${name} deve ser informado"
}

json_field() {
  local json="$1"
  local field="$2"

  jq -r --arg field "${field}" '.[$field] // empty' <<<"${json}"
}
