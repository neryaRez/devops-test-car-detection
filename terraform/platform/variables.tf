variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "car-detector"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "app_bucket_suffix" {
  type        = string
  description = "Globally unique suffix for the application data bucket."
}

variable "enable_eks" {
  type        = bool
  description = "Set true to create EKS (downloads terraform-aws-modules/eks; takes longer to plan/apply)."
  default     = false
}

variable "eks_cluster_version" {
  type    = string
  default = "1.29"
}
