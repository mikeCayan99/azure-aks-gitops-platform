output "resource_group_name" {
  value = azurerm_resource_group.platform.name
}

output "node_resource_group_name" {
  value = azurerm_kubernetes_cluster.platform.node_resource_group
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.platform.name
}

output "registry_login_server" {
  value = azurerm_container_registry.platform.login_server
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.platform.oidc_issuer_url
}
