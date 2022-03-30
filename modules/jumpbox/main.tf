/*
resource "azurerm_public_ip" "pip" {
  name                = "vm-pip"
  location            = var.location
  resource_group_name = var.resource_group
  allocation_method   = "Dynamic"
}
*/

resource "azurerm_network_security_group" "vm_sg" {
  name                = "vm-sg"
  location            = var.location
  resource_group_name = var.resource_group

#  security_rule {
#    name                       = "SSH"
#    priority                   = 1001
#    direction                  = "Inbound"
#    access                     = "Allow"
#    protocol                   = "Tcp"
#    source_port_range          = "*"
#    destination_port_range     = "22"
#    source_address_prefix      = "VirtualNetwork"
#    destination_address_prefix = "*"
#  }
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "vm-nic"
  location            = var.location
  resource_group_name = var.resource_group

  ip_configuration {
    name                          = "vmNicConfiguration"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    #public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface" "vm_nic-w" {
  name                = "vm-nic-w"
  location            = var.location
  resource_group_name = var.resource_group

  ip_configuration {
    name                          = "vmNicConfiguration-w"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    #public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "sg_association-w" {
  network_interface_id      = azurerm_network_interface.vm_nic-w.id
  network_security_group_id = azurerm_network_security_group.vm_sg.id
}

resource "azurerm_network_interface_security_group_association" "sg_association" {
  network_interface_id      = azurerm_network_interface.vm_nic.id
  network_security_group_id = azurerm_network_security_group.vm_sg.id
}

resource "random_password" "adminpassword" {
  keepers = {
    resource_group = var.resource_group
  }

  length      = 10
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azurerm_windows_virtual_machine" "jumpbox-w" {
  name                = "jumpboxvm-w"
  resource_group_name = var.resource_group
  location            = var.location
  size                = "Standard_D4s_v3"
  admin_username      = var.vm_user
  admin_password      = var.vm_password
  # availability_set_id = azurerm_availability_set.DemoAset.id
  network_interface_ids = [azurerm_network_interface.vm_nic-w.id]

  os_disk {
    name                 = "jumpboxwOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter-with-Containers"
    version   = "latest"
  }
}

/*
resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                            = "jumpboxvm"
  location                        = var.location
  resource_group_name             = var.resource_group
  network_interface_ids           = [azurerm_network_interface.vm_nic.id]
  size                            = "Standard_D4s_v3"
  computer_name                   = "jumpboxvm"
  admin_username                  = var.vm_user
#  admin_password                  = random_password.adminpassword.result
  admin_password                  = var.vm_password
  disable_password_authentication = false

  os_disk {
    name                 = "jumpboxOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04.0-LTS"
    version   = "latest"
  }

#  provisioner "remote-exec" {
#    connection {
#      host     = self.public_ip_address
#      type     = "ssh"
#      user     = var.vm_user
#      password = random_password.adminpassword.result
#      password = var.vm_password
#    }

#    inline = [
#      "sudo apt-get update && sudo apt-get install -y apt-transport-https gnupg2",
#      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -",
#      "echo 'deb https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list",
#      "sudo apt-get update",
#      "sudo apt-get install -y kubectl",
#      "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
#    ]
#  }
}
*/

resource "azurerm_private_dns_zone_virtual_network_link" "hublink" {
  name                  = "hubnetdnsconfig"
  resource_group_name   = var.dns_zone_resource_group
  private_dns_zone_name = var.dns_zone_name
  virtual_network_id    = var.vnet_id
}