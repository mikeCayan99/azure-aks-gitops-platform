variable "subscription_id" {
  description = "Explicit subscription selected for this temporary deployment."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant used for authentication."
  type        = string
}

variable "operator_object_id" {
  description = "Entra object ID of the operator granted access to this cluster only."
  type        = string
}

variable "location" {
  description = "Azure region; availability and pricing must be checked before apply."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Dedicated project resource prefix. Do not reuse an existing resource group."
  type        = string
  default     = "aksgitopsdemo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,19}$", var.name_prefix))
    error_message = "Use 3-20 lowercase alphanumeric characters, starting with a letter."
  }
}

variable "registry_name" {
  description = "Globally unique ACR name selected before planning."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{4,49}$", var.registry_name))
    error_message = "Use 5-50 lowercase alphanumeric characters, starting with a letter."
  }
}

variable "kubernetes_version" {
  description = "Exact supported GA patch version selected from the target region."
  type        = string
  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Provide an explicit Kubernetes patch version, for example 1.x.y."
  }
}

variable "api_authorized_ip_ranges" {
  description = "Operator public IPv4 addresses as /32 CIDRs; never an unrestricted range."
  type        = list(string)
  validation {
    condition = length(var.api_authorized_ip_ranges) > 0 && alltrue([
      for cidr in var.api_authorized_ip_ranges : can(cidrhost(cidr, 0)) && can(regex("^[0-9.]+/32$", cidr)) && cidr != "0.0.0.0/32"
    ])
    error_message = "Provide at least one valid operator IPv4 /32 CIDR."
  }
}

variable "node_vm_size" {
  description = "System-node SKU; must support AKS and at least four vCPUs. Check region quota and price."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "cleanup_deadline" {
  description = "ISO-8601 cleanup deadline for resource tags. Informational only, not automatic deletion."
  type        = string
  validation {
    condition     = can(formatdate("YYYY-MM-DD", var.cleanup_deadline))
    error_message = "Use an ISO-8601 timestamp such as 2026-10-02T18:00:00Z."
  }
}
