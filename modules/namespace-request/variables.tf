variable "team_name" {
  description = "Name of the requesting team. Used as a prefix for the namespace and as a label for cost/ownership tracking."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.team_name))
    error_message = "team_name must be lowercase alphanumeric with hyphens, 3-20 characters."
  }
}

variable "environment" {
  description = "Environment tier for this namespace."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "cpu_limit" {
  description = "Total CPU request quota for the namespace (cores)."
  type        = string
  default     = "2"
}

variable "memory_limit" {
  description = "Total memory request quota for the namespace."
  type        = string
  default     = "4Gi"
}

variable "cpu_limit_max" {
  description = "Total CPU hard limit quota for the namespace (cores)."
  type        = string
  default     = "4"
}

variable "memory_limit_max" {
  description = "Total memory hard limit quota for the namespace."
  type        = string
  default     = "8Gi"
}

variable "max_pods" {
  description = "Maximum number of pods allowed in the namespace."
  type        = number
  default     = 20
}

variable "allowed_ingress_namespaces" {
  description = "List of namespaces allowed to send ingress traffic to this namespace (e.g. ['ingress-nginx', 'monitoring']). Empty list means default-deny with no exceptions."
  type        = list(string)
  default     = ["ingress-nginx", "monitoring"]
}

variable "owner_email" {
  description = "Contact email for the requesting team, stored as a namespace annotation."
  type        = string
  default     = ""
}
