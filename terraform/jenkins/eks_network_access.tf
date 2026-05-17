data "aws_eks_cluster" "jenkins_cluster" {
  name = data.aws_ssm_parameter.eks_cluster_name.value
}

resource "aws_security_group_rule" "jenkins_to_eks_api" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = data.aws_eks_cluster.jenkins_cluster.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.jenkins.id
  description              = "Allow Jenkins to access the private EKS API endpoint"
}