#!/usr/bin/env bash

set -euo pipefail

region="${TF_STATE_REGION:-${AWS_REGION:-us-east-1}}"
bucket="${TF_STATE_BUCKET:-}"
shared_name="${SHARED_INFRA_NAME:-${EKS_CLUSTER_NAME:-eks-lab}}"

if [[ -z "${bucket}" ]]; then
  account_id="$(aws --region "${region}" sts get-caller-identity --query Account --output text)"
  bucket="tf-shared-${shared_name}-${account_id}-${region}"
fi

printf 'bucket=%s\n' "${bucket}"
printf 'region=%s\n' "${region}"
printf 'dynamodb_table=%s\n' "${TF_STATE_DYNAMODB_TABLE:-}"
