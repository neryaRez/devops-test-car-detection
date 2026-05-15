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
  description = "Environment name."
  default     = "test"
}

variable "instance_type" {
  type        = string
  description = "Jenkins EC2 instance type."
  default     = "t3.medium"
}

variable "root_volume_gb" {
  type        = number
  description = "Root EBS volume size in GiB."
  default     = 50
}

variable "ssh_key_name" {
  type        = string
  description = "Optional EC2 key pair name. Not required when using SSM."
  default     = ""
}

variable "jenkins_port" {
  type        = number
  description = "Jenkins UI port used for SSM port forwarding."
  default     = 8080
}