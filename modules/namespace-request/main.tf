locals {
  namespace_name = "${var.team_name}-${var.environment}"

  common_labels = {
    "platform.io/managed-by" = "idp"
    "platform.io/team"       = var.team_name
    "platform.io/environment" = var.environment
  }
}

resource "kubernetes_namespace" "this" {
  metadata {
    name   = local.namespace_name
    labels = local.common_labels

    annotations = {
      "platform.io/owner-email"    = var.owner_email
      "platform.io/provisioned-by" = "idp-terraform"
    }
  }
}

resource "kubernetes_resource_quota" "this" {
  metadata {
    name      = "default-quota"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.cpu_limit
      "requests.memory" = var.memory_limit
      "limits.cpu"      = var.cpu_limit_max
      "limits.memory"   = var.memory_limit_max
      "pods"            = tostring(var.max_pods)
    }
  }
}

resource "kubernetes_limit_range" "this" {
  metadata {
    name      = "default-limits"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "250m"
        memory = "256Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

# Default-deny all ingress, then explicitly allow from platform namespaces
resource "kubernetes_network_policy" "default_deny_ingress" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "allow_platform_ingress" {
  count = length(var.allowed_ingress_namespaces) > 0 ? 1 : 0

  metadata {
    name      = "allow-platform-ingress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    dynamic "ingress" {
      for_each = var.allowed_ingress_namespaces
      content {
        from {
          namespace_selector {
            match_labels = {
              "kubernetes.io/metadata.name" = ingress.value
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_account" "default" {
  metadata {
    name      = "${var.team_name}-default"
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.common_labels
  }
}

resource "kubernetes_role" "namespace_admin" {
  metadata {
    name      = "namespace-admin"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  rule {
    api_groups = ["", "apps", "batch", "networking.k8s.io"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding" "namespace_admin_binding" {
  metadata {
    name      = "${var.team_name}-admin-binding"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.namespace_admin.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.default.metadata[0].name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
}
