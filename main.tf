# Locals block for hardcoded names
locals {
  resource_group                 = data.azurerm_resource_group.project-rg.name
  prefix                         = lower(var.prefix)
  environment                    = lower(var.environment)
  prefix_minus                   = replace(local.prefix, "-", "")
  location                       = var.location 
  vnet                           = azurerm_virtual_network.vnet.name
  backend_address_pool_name      = "${local.vnet}-beap"
  frontend_port_name             = "${local.vnet}-feport"
  frontend_ip_configuration_name = "${local.vnet}-feip"
  http_setting_name              = "${local.vnet}-be-htst"
  listener_name                  = "${local.vnet}-httplstn"
  request_routing_rule_name      = "${local.vnet}-rqrt"
  app_gateway_subnet_name        = "appgwsubnet"
  tags = { 
    created_by = "Terraform" 
  }
}

# User Assigned Identities 
resource "azurerm_user_assigned_identity" "aksIdentity" {
  location            = local.location
  resource_group_name = local.resource_group 
  name                = "identity1"
  tags                = local.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.virtual_network_name
  location            = local.location
  resource_group_name = local.resource_group 
  address_space       = [var.virtual_network_address_prefix]

  subnet {
    name           = var.aks_subnet_name
    address_prefix = var.aks_subnet_address_prefix
  }

  subnet {
    name           = "appgwsubnet"
    address_prefix = var.app_gateway_subnet_address_prefix
  }

  tags = local.tags
}

data "azurerm_subnet" "kubesubnet" {
  name                 = var.aks_subnet_name
  virtual_network_name = local.vnet
  resource_group_name  = local.resource_group 
  depends_on           = [azurerm_virtual_network.vnet]
}

data "azurerm_subnet" "appgwsubnet" {
  name                 = "appgwsubnet"
  virtual_network_name = local.vnet
  resource_group_name  = local.resource_group 
  depends_on           = [azurerm_virtual_network.vnet]
}

#Public Public Ip 
resource "azurerm_public_ip" "pub_ip" {
  name                = "publicIp1"
  location            = local.location
  resource_group_name = local.resource_group 
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.tags
}

resource "azurerm_application_gateway" "network" {
  name                = var.app_gateway_name
  location            = local.location
  resource_group_name = local.resource_group 

  sku {
    name     = var.app_gateway_sku
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = data.azurerm_subnet.appgwsubnet.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_port {
    name = "httpsPort"
    port = 443
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.pub_ip.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 1
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }

  tags = local.tags

  depends_on = [azurerm_virtual_network.vnet, azurerm_public_ip.pub_ip]
}

resource "azurerm_role_assignment" "ra1" {
  scope                = data.azurerm_subnet.kubesubnet.id
  role_definition_name = "Network Contributor"
  principal_id         = var.aks_service_principal_object_id

  depends_on = [azurerm_virtual_network.vnet]
}

resource "azurerm_role_assignment" "ra2" {
  scope                = azurerm_user_assigned_identity.aksIdentity.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = var.aks_service_principal_object_id
  depends_on           = [azurerm_user_assigned_identity.aksIdentity]
}

resource "azurerm_role_assignment" "ra3" {
  scope                = azurerm_application_gateway.network.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.askIdentity.principal_id
  depends_on           = [azurerm_user_assigned_identity.aksIdentity, azurerm_application_gateway.network]
}

resource "azurerm_role_assignment" "ra4" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.aksIdentity.principal_id
  depends_on           = [azurerm_user_assigned_identity.aksIdentity, azurerm_application_gateway.network]
}

resource "azurerm_kubernetes_cluster" "k8s" {
  name                = var.aks_name
  location            = local.location
  resource_group_name = local.resource_group 
  dns_prefix          = var.aks_dns_prefix

  http_application_routing_enabled = false

  linux_profile {
    admin_username = var.vm_user_name

    ssh_key {
      key_data = file(var.public_ssh_key_path)
    }
  }

  default_node_pool {
    name            = "agentpool"
    node_count      = var.aks_agent_count
    vm_size         = var.aks_agent_vm_size
    os_disk_size_gb = var.aks_agent_os_disk_size
    vnet_subnet_id  = data.azurerm_subnet.kubesubnet.id
  }

  service_principal {
    client_id     = var.aks_service_principal_app_id
    client_secret = var.aks_service_principal_client_secret
  }

  network_profile {
    network_plugin     = "azure"
    dns_service_ip     = var.aks_dns_service_ip
    docker_bridge_cidr = var.aks_docker_bridge_cidr
    service_cidr       = var.aks_service_cidr
  }

  role_based_access_control {
    enabled = var.aks_enable_rbac
  }

  depends_on = [azurerm_virtual_network.vnet, azurerm_application_gateway.network]
  tags       = local.tags
}
