#!/usr/bin/env bash
set -euo pipefail
for name in ARM_CLIENT_ID ARM_TENANT_ID ARM_SUBSCRIPTION_ID TF_STATE_ACCOUNT TF_STATE_CONTAINER TF_STATE_KEY TF_VAR_registry_name TF_VAR_kubernetes_version TF_VAR_operator_object_id TF_VAR_api_authorized_ip_ranges TF_VAR_cleanup_deadline TF_VAR_name_prefix TF_VAR_location TF_VAR_node_vm_size; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing configuration: $name" >&2
    exit 1
  fi
done
printf 'terraform { backend "azurerm" {} }\n' > infrastructure/azure/backend.generated.tf
terraform -chdir=infrastructure/azure init -input=false -lockfile=readonly \
  -backend-config="storage_account_name=$TF_STATE_ACCOUNT" \
  -backend-config="container_name=$TF_STATE_CONTAINER" \
  -backend-config="key=$TF_STATE_KEY" \
  -backend-config="use_azuread_auth=true" \
  -backend-config="use_oidc=true"
