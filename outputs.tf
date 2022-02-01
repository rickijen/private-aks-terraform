output "ssh_command" {
  value = "ssh ${module.jumpbox.jumpbox_username}@${module.jumpbox.jumpbox_ip}"
}

output "azurerm_log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.default.name
}

output "kube_vnet_name" {
  value = "${random_pet.prefix.id}-kube-vnet"
}

output "hub_vnet_name" {
  value = "${random_pet.prefix.id}-hub-vnet"
}

output "hub_vnet_id" {
  value = "${module.hub_network.vnet_id}"
}

output "aks_subnet_prefix" {
  value = "10.10.5.0/24"
}

output "aks_identity_id" {
  value = azurerm_user_assigned_identity.uai.principal_id
}