output "jenkins_instance_id" {
  value       = aws_instance.jenkins.id
  description = "Jenkins EC2 instance ID. Use this with SSM port forwarding."
}

output "jenkins_private_ip" {
  value       = aws_instance.jenkins.private_ip
  description = "Private IP address of the Jenkins controller."
}

output "jenkins_role_arn" {
  value       = aws_iam_role.jenkins.arn
  description = "IAM role ARN used by Jenkins EC2."
}

output "ssm_port_forward_command" {
  value = "aws ssm start-session --target ${aws_instance.jenkins.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${var.jenkins_port}\"],\"localPortNumber\":[\"${var.jenkins_port}\"]}'"
}