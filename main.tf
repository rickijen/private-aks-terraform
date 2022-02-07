resource "random_pet" "prefix" {}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.87.0"
    }
  }
}

provider "azurerm" {
  features {}
}

#
# Use remote state from the "create-resource-groups" workspace
# The reason is we need to create the resource groups first, assign
# Terraform arm client as the owner in order to assign RBAC roles to
# AKS cluster
#
data "terraform_remote_state" "rg" {
  backend = "remote"

  config = {
    organization = "greensugarcake"
    workspaces = {
      name = "resource-groups"
    }
  }
}

#data "azurerm_resource_group" "vnet" {
#  name      = data.terraform_remote_state.rg.outputs.resource_group_vnet_name
#  #location  = data.terraform_remote_state.rg.outputs.location
#}

#data "azurerm_resource_group" "kube" {
#  name      = data.terraform_remote_state.rg.outputs.resource_group_kube_name
#  #location  = data.terraform_remote_state.rg.outputs.location
#}

resource "azurerm_user_assigned_identity" "uai" {
  resource_group_name = data.terraform_remote_state.rg.outputs.resource_group_kube_name
  location            = data.terraform_remote_state.rg.outputs.location

  name = "uai-${random_pet.prefix.id}-aks"
}

module "hub_network" {
  source              = "./modules/vnet"
  resource_group_name = data.terraform_remote_state.rg.outputs.resource_group_vnet_name
  location            = data.terraform_remote_state.rg.outputs.location
  vnet_name           = "${random_pet.prefix.id}-hub-vnet"
  address_space       = ["10.10.0.0/22"]
  subnets = [
    {
      name : "AzureFirewallSubnet"
      address_prefixes : ["10.10.0.0/24"]
    },
    {
      name : "jumpbox-subnet"
      address_prefixes : ["10.10.1.0/24"]
    }
  ]
}

module "kube_network" {
  source              = "./modules/vnet"
  resource_group_name = data.terraform_remote_state.rg.outputs.resource_group_kube_name
  location            = data.terraform_remote_state.rg.outputs.location
  vnet_name           = "${random_pet.prefix.id}-kube-vnet"
  address_space       = ["10.10.4.0/22"]
  subnets = [
    {
      name : "aks-subnet"
      address_prefixes : ["10.10.5.0/24"]
    }
  ]
}

module "vnet_peering" {
  source              = "./modules/vnet_peering"
  vnet_1_name         = "${random_pet.prefix.id}-hub-vnet"
  vnet_1_id           = module.hub_network.vnet_id
  vnet_1_rg           = data.terraform_remote_state.rg.outputs.resource_group_vnet_name
  vnet_2_name         = "${random_pet.prefix.id}-kube-vnet"
  vnet_2_id           = module.kube_network.vnet_id
  vnet_2_rg           = data.terraform_remote_state.rg.outputs.resource_group_kube_name
  peering_name_1_to_2 = "HubToSpoke1"
  peering_name_2_to_1 = "Spoke1ToHub"
}

module "firewall" {
  source         = "./modules/firewall"
  resource_group = data.terraform_remote_state.rg.outputs.resource_group_vnet_name
  location       = data.terraform_remote_state.rg.outputs.location
  pip_name       = "${random_pet.prefix.id}-fw-ip"
  fw_name        = "${random_pet.prefix.id}-fw"
  subnet_id      = module.hub_network.subnet_ids["AzureFirewallSubnet"]
}

module "routetable" {
  source             = "./modules/route_table"
  resource_group     = data.terraform_remote_state.rg.outputs.resource_group_vnet_name
  location           = data.terraform_remote_state.rg.outputs.location
  rt_name            = "${random_pet.prefix.id}_fw_rt"
  r_name             = "${random_pet.prefix.id}_fw_r"
  firewal_private_ip = module.firewall.fw_private_ip
  subnet_id          = module.kube_network.subnet_ids["aks-subnet"]
}

resource "random_id" "log_analytics_workspace_name_suffix" {
    byte_length = 8
}

resource "azurerm_log_analytics_workspace" "default" {
    # The WorkSpace name has to be unique across the whole of azure, not just the current subscription/tenant.
    name                = "${random_pet.prefix.id}-${random_id.log_analytics_workspace_name_suffix.dec}"
    location            = data.terraform_remote_state.rg.outputs.location
    resource_group_name = data.terraform_remote_state.rg.outputs.resource_group_kube_name
    sku                 = var.log_analytics_workspace_sku
}

resource "azurerm_log_analytics_solution" "default" {
    solution_name         = "ContainerInsights"
    location              = azurerm_log_analytics_workspace.default.location
    resource_group_name   = data.terraform_remote_state.rg.outputs.resource_group_kube_name
    workspace_resource_id = azurerm_log_analytics_workspace.default.id
    workspace_name        = azurerm_log_analytics_workspace.default.name

    plan {
        publisher = "Microsoft"
        product   = "OMSGallery/ContainerInsights"
    }
}

# Need to enable policy in the addon_profile
resource "azurerm_resource_group_policy_assignment" "auditaks" {
    name                  = "audit-${random_pet.prefix.id}-aks"
    resource_group_id     = data.terraform_remote_state.rg.outputs.resource_group_kube_id
    policy_definition_id  = var.azure_policy_k8s_initiative
}

resource "azurerm_kubernetes_cluster" "privateaks" {
  name                    = "${random_pet.prefix.id}-aks"
  location                = data.terraform_remote_state.rg.outputs.location
#  kubernetes_version      = data.azurerm_kubernetes_service_versions.current.latest_version
  resource_group_name     = data.terraform_remote_state.rg.outputs.resource_group_kube_name
  dns_prefix              = "${random_pet.prefix.id}-aks"
  private_cluster_enabled = true
  # az aks get-credentials --admin will fail. Non-audible backdoor is closed
  local_account_disabled  = true

  # Planned Maintenance window
  maintenance_window {
    allowed {
      day = "Saturday"
      hours = [21, 23]
    }
    allowed {
      day = "Sunday"
      hours = [5, 6]
    }
    not_allowed {
      start = "2022-05-26T03:00:00Z"
      end = "2022-05-30T12:00:00Z"
    }
  }

  default_node_pool {
    name                = "default"
    #node_count         = var.nodepool_nodes_count
    vm_size             = "Standard_D2_v2"
    os_disk_size_gb     = 30
    type                = "VirtualMachineScaleSets"
    availability_zones  = ["1", "2"]
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 6
    vnet_subnet_id      = module.kube_network.subnet_ids["aks-subnet"]
    only_critical_addons_enabled = true
    # Upgrade settings
    upgrade_settings {
      max_surge = "30%"
    }
    # This needs to be the same as the k8s verion of control plane.
    # If orchestrator_version is missing, only the control plane k8s will be upgraded, not the nodepools
    # orchestrator_version = "1.21.2"
  }

  role_based_access_control {
    enabled = true
    azure_active_directory {
      managed                = true
      azure_rbac_enabled     = true
      admin_group_object_ids = [var.admin_group_obj_id]
      # append comma separated group obj IDs
      #admin_group_object_ids = [azuread_group.aks_administrators.object_id]
    }
  }

  identity {
    #type = "SystemAssigned"
    type = "UserAssigned"
    user_assigned_identity_id = azurerm_user_assigned_identity.uai.id
  }

  # Add On's
  addon_profile {
      oms_agent {
        enabled                    = true
        log_analytics_workspace_id = azurerm_log_analytics_workspace.default.id
      }
      azure_policy { enabled = true }
      # need to review open policy agent next time
      # https://docs.microsoft.com/en-us/azure/governance/policy/concepts/policy-for-kubernetes

      # Open Service Mesh: https://docs.microsoft.com/en-us/azure/aks/open-service-mesh-deploy-addon-az-cli
      open_service_mesh { enabled = true }

      # Greenfield AGIC - this will create a new App Gateway in MC_ resource group
      # ingress_application_gateway {
      #   enabled   = true
      #   subnet_id = azurerm_subnet.appgw.id
      # }

      #kube_dashboard {
      #  enabled = true
      #}
  }

  network_profile {
    # docker_bridge_cidr = var.network_docker_bridge_cidr
    # dns_service_ip     = var.network_dns_service_ip
    network_plugin     = "kubenet"
    outbound_type      = "userDefinedRouting"
    # service_cidr       = var.network_service_cidr
    load_balancer_sku  = "standard"
    # network_policy     = "calico" # network policy "azure" not supported
  }

  depends_on = [module.routetable]
}

# RBAC role assignment for the AKS UAI
resource "azurerm_role_assignment" "netcontributor-subnet" {
  role_definition_name = "Network Contributor"
  scope                = module.kube_network.subnet_ids["aks-subnet"]
  principal_id         = azurerm_user_assigned_identity.uai.principal_id
}

resource "azurerm_role_assignment" "netcontributor-udr" {
  role_definition_name = "Network Contributor"
  scope                = module.routetable.udr_id
  principal_id         = azurerm_user_assigned_identity.uai.principal_id
}

# User mode node pool - Linux
resource "azurerm_kubernetes_cluster_node_pool" "usrpl1" {
  name                  = "upool1"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.privateaks.id
  vm_size               = "Standard_DS2_v2"
  # node_count            = 3
  availability_zones    = ["1", "2"]
  enable_auto_scaling   = true
  min_count             = 2
  max_count             = 6

  # Upgrade settings
  upgrade_settings {
    max_surge = "30%"
  }

  tags = {
    environment = "Premera"
  }
}

# Jumpbox for kubectl
module "jumpbox" {
  source                  = "./modules/jumpbox"
  location                = data.terraform_remote_state.rg.outputs.location
  resource_group          = data.terraform_remote_state.rg.outputs.resource_group_vnet_name
  vnet_id                 = module.hub_network.vnet_id
  subnet_id               = module.hub_network.subnet_ids["jumpbox-subnet"]
  dns_zone_name           = join(".", slice(split(".", azurerm_kubernetes_cluster.privateaks.private_fqdn), 1, length(split(".", azurerm_kubernetes_cluster.privateaks.private_fqdn))))
  dns_zone_resource_group = azurerm_kubernetes_cluster.privateaks.node_resource_group
  vm_password             = var.jumpbox_password
}

/*
sudo apt-get update && sudo apt-get install -y apt-transport-https gnupg2
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-get update
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
# OSM
OSM_VERSION=v0.11.1
curl -sL "https://github.com/openservicemesh/osm/releases/download/$OSM_VERSION/osm-$OSM_VERSION-linux-amd64.tar.gz" | tar -vxzf -
sudo mv ./linux-amd64/osm /usr/local/bin/osm
sudo chmod +x /usr/local/bin/osm
*/
