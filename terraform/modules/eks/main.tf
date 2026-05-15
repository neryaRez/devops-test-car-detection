module "cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = "${var.name_prefix}-eks"
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      name           = "${var.name_prefix}-default"
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      capacity_type = var.node_capacity_type
      disk_size     = var.node_disk_size

      subnet_ids = var.subnet_ids

      labels = {
        workload = "car-detector"
      }

      tags = {
        Name        = "${var.name_prefix}-eks-node"
        Environment = var.environment
      }
    }
  }

  tags = {
    Name        = "${var.name_prefix}-eks"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}