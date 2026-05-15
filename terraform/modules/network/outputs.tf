output "vpc_id" {
  value       = aws_vpc.this.id
  description = "VPC ID."
}

output "vpc_cidr_block" {
  value       = aws_vpc.this.cidr_block
  description = "VPC CIDR block."
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "Public subnet IDs, mainly for NAT Gateway or optional public resources."
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "Private subnet IDs for EKS nodes and Jenkins."
}

output "private_route_table_id" {
  value       = aws_route_table.private.id
  description = "Private route table ID."
}

output "vpc_endpoint_security_group_id" {
  value       = aws_security_group.vpc_endpoints.id
  description = "Security group attached to interface VPC endpoints."
}