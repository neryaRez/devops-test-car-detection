module "cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = "${var.name_prefix}-eks"
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = false

  eks_managed_node_groups = {
    default = {
      name           = "${var.name_prefix}-default"
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 4
      desired_size   = 2
    }
  }

  tags = {
    Name        = "${var.name_prefix}-eks"
    Environment = var.environment
  }
}
