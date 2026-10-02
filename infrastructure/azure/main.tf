locals {
  tags = {
    Project         = "azure-aks-gitops-platform"
    Environment     = "temporary-integration"
    ManagedBy       = "Terraform"
    CleanupDeadline = var.cleanup_deadline
  }
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-${var.name_prefix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_container_registry" "platform" {
  name                 = var.registry_name
  resource_group_name  = azurerm_resource_group.platform.name
  location             = azurerm_resource_group.platform.location
  sku                  = "Basic"
  admin_enabled        = false
  role_assignment_mode = "LegacyRegistryPermissions"
  tags                 = local.tags
}

resource "azurerm_kubernetes_cluster" "platform" {
  name                              = "aks-${var.name_prefix}"
  location                          = azurerm_resource_group.platform.location
  resource_group_name               = azurerm_resource_group.platform.name
  node_resource_group               = "rg-${var.name_prefix}-nodes"
  dns_prefix                        = var.name_prefix
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = "Free"
  role_based_access_control_enabled = true
  local_account_disabled            = true
  run_command_enabled               = false
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  default_node_pool {
    name                        = "system"
    node_count                  = 2
    vm_size                     = var.node_vm_size
    os_disk_size_gb             = 64
    os_disk_type                = "Managed"
    max_pods                    = 30
    temporary_name_for_rotation = "systemtemp"
    tags                        = local.tags
  }

  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type = "SystemAssigned"
  }

  azure_active_directory_role_based_access_control {
    tenant_id          = var.tenant_id
    azure_rbac_enabled = true
  }

  api_server_access_profile {
    authorized_ip_ranges = var.api_authorized_ip_ranges
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  tags = local.tags
}

resource "azurerm_role_assignment" "image_pull" {
  scope                            = azurerm_container_registry.platform.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.platform.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "cluster_user" {
  scope                = azurerm_kubernetes_cluster.platform.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.operator_object_id
}

resource "azurerm_role_assignment" "cluster_admin" {
  scope                = azurerm_kubernetes_cluster.platform.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.operator_object_id
}
