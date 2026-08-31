terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    # Configure via -backend-config or a backend.hcl file, e.g.:
    # bucket = "idp-platform-tfstate"
    # key    = "idp-platform/terraform.tfstate"
    # region = "us-east-1"
    # dynamodb_table = "idp-platform-tf-locks"
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Uses exec-based auth (aws eks get-token) instead of a static
# kubeconfig so this works both locally (with your AWS CLI creds) and
# in GitHub Actions (with the OIDC-assumed role from configure-aws-credentials).
# Requires the AWS CLI to be on PATH wherever `terraform apply` runs.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.eks_cluster_name, "--region", var.aws_region]
  }
}

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster (reused from the gitops-pipeline project)."
  type        = string
}

variable "aws_region" {
  description = "AWS region the EKS cluster lives in."
  type        = string
  default     = "us-east-1"
}

# One namespace-request module instance per file in environments/requests/.
# In CI, this is driven by a for_each over yamldecode() of each request file
# (see .github/workflows/provision.yml) so this file itself stays static
# and requests are added purely by dropping a new YAML file — no .tf edits needed.
locals {
  request_files = fileset("${path.module}/environments/requests", "*.yaml")
  requests = {
    for f in local.request_files :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/environments/requests/${f}"))
  }
}

module "namespace" {
  source   = "./modules/namespace-request"
  for_each = local.requests

  team_name         = each.value.team_name
  environment       = try(each.value.environment, "dev")
  cpu_limit         = try(each.value.cpu_limit, "2")
  memory_limit      = try(each.value.memory_limit, "4Gi")
  cpu_limit_max     = try(each.value.cpu_limit_max, "4")
  memory_limit_max  = try(each.value.memory_limit_max, "8Gi")
  max_pods          = try(each.value.max_pods, 20)
  owner_email       = try(each.value.owner_email, "")
}

output "provisioned_namespaces" {
  value = { for k, m in module.namespace : k => m.namespace_name }
}
