# Locals block for hardcoded names
locals {
  resource_group                 = data.azurerm_resource_group.project-rg.name
  prefix                         = lower(var.prefix)
  environment                    = lower(var.environment)
  prefix_minus                   = replace(local.prefix, "-", "")
  location                       = var.location 
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${local.prefix}-${local.environment}-vnet"
  location            = local.location 
  resource_group_name = local.resource_group 
  address_space       = [var.virtual_network_address_prefix]

  subnet {
    name           = var.aks_subnet_name
    address_prefix = var.aks_subnet_address_prefix
  }
}

data "azurerm_subnet" "kubesubnet" {
  name                 = var.aks_subnet_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = local.resource_group 
  depends_on           = [azurerm_virtual_network.vnet]
}

resource "azurerm_role_assignment" "ra1" {
  scope                = data.azurerm_resource_group.project-rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.k8s.kubelet_identity[0].object_id
}

resource "azurerm_role_assignment" "ra2" {
  scope                = data.azurerm_resource_group.project-rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.k8s.identity[0].principal_id
}

resource "azurerm_role_assignment" "ra3" {
  scope                = data.azurerm_subnet.kubesubnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.k8s.identity[0].principal_id
}

resource "azurerm_kubernetes_cluster" "k8s" {
  name                = var.aks_name
  location            = local.location
  resource_group_name = local.resource_group 
  dns_prefix          = var.aks_dns_prefix

  http_application_routing_enabled  = false
  role_based_access_control_enabled = true


  linux_profile {
    admin_username = var.vm_user_name
    ssh_key {
      key_data = file(var.public_ssh_key_path)
    }
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = false
  }

  identity {
    type  = "SystemAssigned"
  }

  default_node_pool {
    name            = "agentpool"
    node_count      = var.aks_agent_count
    vm_size         = var.aks_agent_vm_size
    os_disk_size_gb = var.aks_agent_os_disk_size
    vnet_subnet_id  = data.azurerm_subnet.kubesubnet.id
  }

  network_profile {
    network_plugin     = "kubenet"
    dns_service_ip     = var.aks_dns_service_ip
    docker_bridge_cidr = var.aks_docker_bridge_cidr
    service_cidr       = var.aks_service_cidr
  }
}

resource "azurerm_key_vault" "vault" {
  name                = "${local.prefix}-${local.environment}-kv"
  location            = local.location
  resource_group_name = local.resource_group
  sku_name            = "standard"
  tenant_id           = data.azurerm_client_config.current.tenant_id
}

resource "azurerm_key_vault_access_policy" "pipeline-access" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  key_permissions = [
    "Get", "List", "Create", "Delete", "Encrypt", "Decrypt", "UnwrapKey", "WrapKey", "Purge", "Recover", "Restore"
  ]
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge", "Recover", "Restore"
  ]
  certificate_permissions = [
    "Backup", "Create", "Delete", "Get", "Import", "List", "Purge", "Recover", "Restore", "Update"
  ]
  storage_permissions = [
    "Get", "List", "Set", "Delete", "Purge", "Recover", "Restore"
  ]
}

resource "azurerm_key_vault_access_policy" "k8s-secrets-access" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_kubernetes_cluster.k8s.key_vault_secrets_provider[0].secret_identity[0].object_id
  key_permissions = [
    "Get", "List", "Create", "Delete", "Encrypt", "Decrypt", "UnwrapKey", "WrapKey", "Purge", "Recover", "Restore"
  ]
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge", "Recover", "Restore"
  ]
  certificate_permissions = [
    "Backup", "Create", "Delete", "Get", "Import", "List", "Purge", "Recover", "Restore", "Update"
  ]
  storage_permissions = [
    "Get", "List", "Set", "Delete", "Purge", "Recover", "Restore"
  ]
}

resource "azurerm_public_ip" "nginx" {
  name                = "NGINXPublicIp"
  location            = local.location
  resource_group_name = local.resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.k8s.kube_config.0.client_certificate
  sensitive = true
}

output "kube_config" {
  value = azurerm_kubernetes_cluster.k8s.kube_config_raw
  sensitive = true
}

output "secret_identity_client_id" {
  value = azurerm_kubernetes_cluster.k8s.key_vault_secrets_provider[0].secret_identity[0].object_id
}

output "public_ip" {
  value = azurerm_public_ip.nginx.ip_address
}
