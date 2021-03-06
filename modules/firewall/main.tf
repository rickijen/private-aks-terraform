resource "azurerm_public_ip" "pip" {
  name                = var.pip_name
  resource_group_name = var.resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "fw" {
  name                = var.fw_name
  location            = var.location
  resource_group_name = var.resource_group

  ip_configuration {
    name                 = "fw_ip_config"
    subnet_id            = var.subnet_id
    public_ip_address_id = azurerm_public_ip.pip.id
  }
}

resource "azurerm_firewall_network_rule_collection" "time" {
  name                = "time"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group
  priority            = 101
  action              = "Allow"

  rule {
    description           = "aks node time sync rule"
    name                  = "allow network"
    source_addresses      = ["*"]
    destination_ports     = ["123"]
    destination_addresses = ["*"]
    protocols             = ["UDP"]
  }
}

resource "azurerm_firewall_network_rule_collection" "dns" {
  name                = "dns"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group
  priority            = 102
  action              = "Allow"

  rule {
    description           = "aks node dns rule"
    name                  = "allow network"
    source_addresses      = ["*"]
    destination_ports     = ["53"]
    destination_addresses = ["*"]
    protocols             = ["UDP"]
  }
}

resource "azurerm_firewall_network_rule_collection" "servicetags" {
  name                = "servicetags"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group
  priority            = 110
  action              = "Allow"

  rule {
    description       = "allow service tags"
    name              = "allow service tags"
    source_addresses  = ["*"]
    destination_ports = ["*"]
    protocols         = ["Any"]

    destination_addresses = [
      "AzureContainerRegistry",
      "MicrosoftContainerRegistry",
      "AzureActiveDirectory"
    ]
  }
}

resource "azurerm_firewall_application_rule_collection" "aksbasics" {
  name                = "aksbasics"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group
  priority            = 101
  action              = "Allow"

  rule {
    name             = "allow network"
    source_addresses = ["*"]

    target_fqdns = [
      "*.cdn.mscr.io",
      "mcr.microsoft.com",
      "*.data.mcr.microsoft.com",
      "management.azure.com",
      "login.microsoftonline.com",
      "acs-mirror.azureedge.net",
      "dc.services.visualstudio.com",  # Azure Policy: Azure Policy add-on that sends telemetry data to applications insights endpoint.
      "*.opinsights.azure.com",
      "*.oms.opinsights.azure.com",
      "*.microsoftonline.com",
      "*.monitoring.azure.com",
      "data.policy.core.windows.net",  # Azure Policy: This address is used to pull the Kubernetes policies and to report cluster compliance status to policy service.
      "store.policy.core.windows.net"  # Azure Policy: This address is used to pull the Gatekeeper artifacts (constraint templates) of built-in policies.
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
}

resource "azurerm_firewall_application_rule_collection" "osupdates" {
  name                = "osupdates"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group
  priority            = 102
  action              = "Allow"

  rule {
    name             = "allow network"
    source_addresses = ["*"]

    target_fqdns = [
      "download.opensuse.org",
      "security.ubuntu.com",
      "ntp.ubuntu.com",
      "packages.microsoft.com",
      "snapcraft.io"
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
}

resource "azurerm_firewall_application_rule_collection" "publicimages" {
  name                = "publicimages"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group
  priority            = 103
  action              = "Allow"

  rule {
    name             = "allow network"
    source_addresses = ["*"]

    target_fqdns = [
      "auth.docker.io",
      "registry-1.docker.io",
      "production.cloudflare.docker.com",
      "*.blob.core.windows.net", # This is needed for Bridge to K8S to work.
      "*.azure-api.net",         # APIM self-hosted gateway
      "*.azure.com",             # APIM self-hosted gateway
      "*.table.core.windows.net" # APIM self-hosted gateway
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
}

resource "azurerm_firewall_application_rule_collection" "test" {
  name                = "test"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group
  priority            = 104
  action              = "Allow"

  rule {
    name             = "allow network"
    source_addresses = ["*"]

    target_fqdns = [
      "*.bing.com"
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
}