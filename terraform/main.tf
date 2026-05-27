locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  eks_admin_access_entries = var.eks_admin_role_arn == "" ? {} : {
    terraform_admin = {
      principal_arn = var.eks_admin_role_arn

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

data "aws_caller_identity" "current" {}

# ─── VPC ─────────────────────────────────────────────────────────────────────
# Two public subnets (Load Balancer facing) and two private subnets
# (worker nodes) spread across two AZs for high availability.
# A single NAT Gateway is used to keep costs low for non-production.

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "./modules/vpc"

  vpc_subnet_az_id = var.az_ids
  vpc_cidr         = var.vpc_cidr
}

# ─── ECR ─────────────────────────────────────────────────────────────────────
# Private container registries for each microservice.
# Docker images built by CI/CD are pushed here; EKS nodes pull from here.

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  services     = var.ecr_services
  tags         = local.common_tags
}

# ─── EKS ─────────────────────────────────────────────────────────────────────
# EKS cluster with worker nodes across 2 AZs, core add-ons,
# and IRSA roles for AWS Load Balancer Controller, EBS CSI, and Cluster Autoscaler.

module "eks" {
  source = "./modules/eks"

  cluster_name    = local.cluster_name
  cluster_version = var.eks_cluster_version

  vpc_id             = module.vpc.output_vpc_id
  private_subnet_ids = module.vpc.output_private_subnets
  public_subnet_ids  = module.vpc.output_public_subnets

  tags = local.common_tags

  access_entries = local.eks_admin_access_entries

  enable_cluster_creator_admin_permissions = var.eks_admin_role_arn == ""
}

# Optional root-level OIDC IAM role (IRSA) for app workloads.
module "root_oidc_iam_role" {
  count  = var.create_root_oidc_iam_role ? 1 : 0
  source = "./modules/oidc_iam_role"

  role_name                  = var.root_oidc_iam_role_name
  oidc_provider_arn          = module.eks.oidc_provider_arn
  namespace_service_accounts = var.root_oidc_namespace_service_accounts

  tags = local.common_tags
}
