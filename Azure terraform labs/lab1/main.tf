data "azurerm_resource_group" "assessment" {
  name = var.resource_group_name
}

resource "random_string" "fqdn" {
  length  = 6
  special = false
  upper   = false
  numeric = false
}

#############################################################################
# NETWORK & SUBNET
#############################################################################

resource "azurerm_network_security_group" "vmss" {
  name                = var.azurerm_network_security_group
  location            = data.azurerm_resource_group.assessment.location
  resource_group_name = data.azurerm_resource_group.assessment.name

  security_rule {
    name                       = "HTTP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "vmss" {
  name                = var.azurerm_virtual_network
  address_space       = ["10.1.0.0/16"]
  location            = data.azurerm_resource_group.assessment.location
  resource_group_name = data.azurerm_resource_group.assessment.name
}

resource "azurerm_subnet" "vmss" {
  name                 = var.azurerm_subnet
  resource_group_name  = data.azurerm_resource_group.assessment.name
  virtual_network_name = azurerm_virtual_network.vmss.name
  address_prefixes     = ["10.1.0.0/16"]
}

resource "azurerm_subnet_network_security_group_association" "vmss" {
  subnet_id                 = azurerm_subnet.vmss.id
  network_security_group_id = azurerm_network_security_group.vmss.id
}

#############################################################################
# PUBLIC IP
#############################################################################

resource "azurerm_public_ip" "vmss" {
  name                = "VMSS-PUBLIC-IP"
  location            = data.azurerm_resource_group.assessment.location
  resource_group_name = data.azurerm_resource_group.assessment.name
  allocation_method   = "Static"
  domain_name_label   = random_string.fqdn.result
  sku                 = "Standard"
}

#############################################################################
# LOAD BALANCER
#############################################################################

resource "azurerm_lb" "vmss" {
  name                = "VMSS-LB"
  location            = data.azurerm_resource_group.assessment.location
  resource_group_name = data.azurerm_resource_group.assessment.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.vmss.id

  }
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  loadbalancer_id = azurerm_lb.vmss.id
  name            = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vmss" {
  name            = "VMSS-PROB"
  loadbalancer_id = azurerm_lb.vmss.id
  port            = var.application_port
}

resource "azurerm_lb_rule" "lbnatrule" {
  loadbalancer_id                = azurerm_lb.vmss.id
  name                           = "LBRuleHTTP"
  protocol                       = "Tcp"
  frontend_port                  = var.application_port
  backend_port                   = var.application_port
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bpepool.id]
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.vmss.id
}

resource "azurerm_lb_nat_pool" "lbnatpoolssh" {
  name                           = "SSH"
  resource_group_name            = var.resource_group_name
  loadbalancer_id                = azurerm_lb.vmss.id
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50119
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}

#############################################################################
# VIRTUAL SCALE SET
#############################################################################

resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = var.virtual_machine_name
  location            = data.azurerm_resource_group.assessment.location
  resource_group_name = data.azurerm_resource_group.assessment.name
  upgrade_mode        = "Manual"
  zones               = ["1", "2"]
  sku                 = "Standard_D2s_v3"
  instances           = var.instances_count

  computer_name_prefix            = "vmlab"
  admin_username                  = var.admin_user
  admin_password                  = var.admin_password
  custom_data                     = base64encode(file("web.conf"))
  disable_password_authentication = false

  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  data_disk {
    lun                  = 0
    caching              = "ReadWrite"
    create_option        = "Empty"
    disk_size_gb         = 10
    storage_account_type = "Premium_LRS"
  }

  network_interface {
    name                          = "terraformnetworkprofile"
    primary                       = true
    enable_accelerated_networking = true
    enable_ip_forwarding          = false
    network_security_group_id     = azurerm_network_security_group.vmss.id

    ip_configuration {
      name                                   = "IPConfiguration"
      subnet_id                              = azurerm_subnet.vmss.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
      load_balancer_inbound_nat_rules_ids    = [azurerm_lb_nat_pool.lbnatpoolssh.id]
      primary                                = true
    }
  }
}

#############################################################################
# AUTOSCALING
#############################################################################

resource "azurerm_monitor_autoscale_setting" "vmss" {
  name                = "AutoscaleSetting"
  resource_group_name = data.azurerm_resource_group.assessment.name
  location            = data.azurerm_resource_group.assessment.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss.id

  profile {
    name = "defaultProfile"

    capacity {
      default = 2
      minimum = 2
      maximum = 10
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
        dimensions {
          name     = "AppName"
          operator = "Equals"
          values   = ["App1"]
        }
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }

  notification {
    email {
      send_to_subscription_administrator    = true
      send_to_subscription_co_administrator = true
      custom_emails                         = ["mhm.heshamo@gmail.com"]
    }
  }
}