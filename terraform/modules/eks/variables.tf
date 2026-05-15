variable "name_prefix" {
  type        = string
  description = "Project/resource name prefix."
}

variable "environment" {
  type        = string
  description = "Environment name used for tagging."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where EKS will be created."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the EKS control plane networking and managed nodes."
}

variable "cluster_version" {
  type        = string
  description = "EKS Kubernetes version."
  default     = "1.29"
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Whether to expose the EKS API endpoint publicly. Default is false for private-first operation."
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to access the public EKS endpoint if public access is enabled."
  default     = []
}

variable "node_instance_types" {
  type        = list(string)
  description = "EC2 instance types for the EKS managed node group."
  default     = ["t3.medium"]
}

variable "node_min_size" {
  type        = number
  description = "Minimum number of EKS worker nodes."
  default     = 1
}

variable "node_max_size" {
  type        = number
  description = "Maximum number of EKS worker nodes."
  default     = 3
}

variable "node_desired_size" {
  type        = number
  description = "Desired number of EKS worker nodes."
  default     = 1
}

variable "node_capacity_type" {
  type        = string
  description = "EKS node capacity type: ON_DEMAND or SPOT."
  default     = "ON_DEMAND"
}

variable "node_disk_size" {
  type        = number
  description = "Disk size in GiB for EKS worker nodes."
  default     = 30
}