variable "aws_region" {
  type        = string
  description = "AWS region."
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Project/resource name prefix."
  default     = "car-detector"
}

variable "environment" {
  type        = string
  description = "Environment name used for tagging."
  default     = "test"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.42.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of Availability Zones/subnet pairs to create."
  default     = 2
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Create a single NAT Gateway for private subnet outbound access."
  default     = true
}

variable "enable_vpc_endpoints" {
  type        = bool
  description = "Create VPC endpoints for private AWS service access."
  default     = true
}

variable "app_bucket_suffix" {
  type        = string
  description = "Optional globally unique suffix for the application data bucket. Defaults to account-id-region."
  default     = null
}

variable "enable_eks" {
  type        = bool
  description = "Set true to create EKS."
  default     = false
}

variable "eks_cluster_version" {
  type        = string
  description = "EKS Kubernetes version."
  default     = "1.29"
}

variable "helm_namespace" {
  type        = string
  description = "Kubernetes namespace for the detector workload."
  default     = "car-detector"
}

variable "detector_service_account_name" {
  type        = string
  description = "Kubernetes ServiceAccount name used by the detector pod."
  default     = "car-detector"
}

variable "eks_endpoint_public_access" {
  type        = bool
  description = "Whether to expose the EKS API endpoint publicly. Default false; Jenkins/SSM should manage the cluster from inside the VPC."
  default     = false
}

variable "eks_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public EKS API endpoint if enabled."
  default     = []
}

variable "eks_node_instance_types" {
  type        = list(string)
  description = "EC2 instance types for the EKS managed node group."
  default     = ["t3.medium"]
}

variable "eks_node_min_size" {
  type        = number
  description = "Minimum number of EKS worker nodes."
  default     = 1
}

variable "eks_node_max_size" {
  type        = number
  description = "Maximum number of EKS worker nodes."
  default     = 3
}

variable "eks_node_desired_size" {
  type        = number
  description = "Desired number of EKS worker nodes."
  default     = 1
}

variable "eks_node_capacity_type" {
  type        = string
  description = "EKS node capacity type: ON_DEMAND or SPOT."
  default     = "ON_DEMAND"
}

variable "eks_node_disk_size" {
  type        = number
  description = "Disk size in GiB for EKS worker nodes."
  default     = 30
}