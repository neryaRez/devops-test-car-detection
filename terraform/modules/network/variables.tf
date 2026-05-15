variable "name_prefix" {
  type        = string
  description = "Project/resource name prefix."
}

variable "environment" {
  type        = string
  description = "Environment tag value."
  default     = "test"
}

variable "aws_region" {
  type        = string
  description = "AWS region, used for VPC endpoint service names."
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

variable "interface_endpoint_services" {
  type        = list(string)
  description = "AWS interface endpoint services to create inside private subnets."
  default = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "sts",
    "ssm",
    "ssmmessages",
    "ec2messages"
  ]
}