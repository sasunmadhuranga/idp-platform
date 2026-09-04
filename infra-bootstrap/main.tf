# infra-bootstrap
#
# Standalone, minimal EKS cluster sized purely to demo idp-platform:
# spin up -> record demo -> destroy. NOT sized for a long-running or
# production cluster. This is deliberately separate from
# idp-platform's own state/module so you can destroy just the cluster
# without touching the namespace-provisioning logic, and vice versa.
#
# Usage:
#   cd infra-bootstrap
#   terraform init
#   terraform apply -var="cluster_name=idp-demo"
#   ... run idp-platform's terraform apply against this cluster ...
#   ... record your demo ...
#   terraform destroy -var="cluster_name=idp-demo"   # tear down when done

terraform {
  required_version = ">= 1.6.0"

  # Configure via -backend-config=backend.hcl (see backend.hcl.example
  # in this directory). Uses the same bucket as idp-platform's own
  # state, but a different key, so the two states stay independent.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

variable "cluster_name" {
  description = "Name for the demo EKS cluster."
  type        = string
  default     = "idp-demo"
}

variable "aws_region" {
  description = "AWS region to create the cluster in."
  type        = string
  default     = "us-east-1"
}

variable "node_instance_type" {
  description = "Instance type for the single managed node group. t3.small keeps cost low; bump to t3.medium if pods get stuck Pending on resource pressure while demoing multiple namespaces."
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  description = "Desired node count. 2 nodes gives enough headroom for ArgoCD + a couple of demo namespaces without immediately hitting t3.small limits."
  type        = number
  default     = 2
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true # cost optimization for a demo cluster — one NAT, not one per AZ
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Purpose                                     = "idp-platform-demo"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  # EKS deprecates old versions ~14 months after release, so this will
  # drift over time. 1.29 was rejected as unsupported during initial
  # testing; bumped to the version that actually worked. If this fails
  # again in the future, check current supported versions with:
  #   aws eks describe-addon-versions --query 'addons[0].addonVersions[0].compatibilities[].clusterVersion' (or the EKS console)
  cluster_version = "1.35"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # Without this, the IAM identity that runs `terraform apply` is NOT
  # automatically granted access inside the cluster's Kubernetes RBAC
  # layer (IAM permissions and K8s RBAC are separate systems in EKS).
  # Omitting this causes an "Unauthorized" error the moment Terraform
  # tries to create any Kubernetes resource (namespace, Helm release,
  # etc.) even though the AWS-level apply succeeded.
  enable_cluster_creator_admin_permissions = true

  # OIDC provider needed for IAM Roles for Service Accounts (IRSA) and
  # for GitHub Actions OIDC federation used by idp-platform's CI.
  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size       = 1
      max_size       = 3
      desired_size   = var.node_desired_size

      capacity_type = "SPOT" # cheaper for a short-lived demo cluster
    }
  }

  tags = {
    Purpose = "idp-platform-demo"
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "6.7.3" # pin a known-working chart version rather than floating "latest"

  # Minimal values: single replica server, no HA — this is a demo
  # cluster, not production ArgoCD.
  set {
    name  = "server.replicas"
    value = "1"
  }
  set {
    name  = "controller.replicas"
    value = "1"
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "argocd_admin_password_command" {
  description = "Run this after apply to retrieve the ArgoCD initial admin password."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
