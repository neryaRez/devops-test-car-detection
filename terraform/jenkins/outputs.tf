output "jenkins_private_ip" {
  value       = aws_instance.jenkins.private_ip
  description = "Use SSM session manager or bastion if instance has no public IP in a private subnet."
}

output "jenkins_instance_id" {
  value = aws_instance.jenkins.id
}
