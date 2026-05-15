variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the EKS control plane and nodes (use public subnets for this scaffold)."
}

variable "cluster_version" {
  type        = string
  description = "EKS Kubernetes version"
  default     = "1.29"
}

variable "environment" {
  type = string
  description = "Environment name used for tagging."
  default = "prod"
}
