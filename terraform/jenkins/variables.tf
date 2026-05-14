variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "car-detector"
}

variable "vpc_id" {
  type        = string
  description = "VPC from platform stack (e.g. module output)."
}

variable "subnet_id" {
  type        = string
  description = "Public subnet for the Jenkins EC2 instance."
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to reach SSH (22) and Jenkins (8080), e.g. 203.0.113.10/32"
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ssh_key_name" {
  type        = string
  description = "Optional EC2 key pair name for SSH."
  default     = ""
}

variable "root_volume_gb" {
  type    = number
  default = 50
}
