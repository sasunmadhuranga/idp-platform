output "namespace_name" {
  description = "Name of the created namespace."
  value       = kubernetes_namespace.this.metadata[0].name
}

output "service_account_name" {
  description = "Default service account created for the team."
  value       = kubernetes_service_account.default.metadata[0].name
}

output "quota_summary" {
  description = "Summary of the resource quota applied to the namespace."
  value = {
    cpu_requests    = var.cpu_limit
    memory_requests = var.memory_limit
    cpu_limits      = var.cpu_limit_max
    memory_limits   = var.memory_limit_max
    max_pods        = var.max_pods
  }
}
