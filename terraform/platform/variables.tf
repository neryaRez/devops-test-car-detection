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