data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "jenkins_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "jenkins" {
  name = "${var.name_prefix}-${var.environment}-jenkins-role"

  assume_role_policy = data.aws_iam_policy_document.jenkins_assume_role.json

  tags = {
    Name        = "${var.name_prefix}-jenkins-role"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.name_prefix}-${var.environment}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "jenkins_inline" {
  statement {
    sid    = "ReadProjectConfigurationFromSSM"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]

    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.name_prefix}/${var.environment}/*"
    ]
  }

  statement {
    sid    = "UseOfficialAppBucket"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${data.aws_ssm_parameter.app_bucket_name.value}"
    ]
  }

  statement {
    sid    = "ReadWriteOfficialAppBucketObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [
      "arn:aws:s3:::${data.aws_ssm_parameter.app_bucket_name.value}/*"
    ]
  }

  statement {
    sid    = "CreateAndConfigureProjectFallbackBuckets"
    effect = "Allow"

    actions = [
      "s3:CreateBucket",
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:PutBucketVersioning",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration"
    ]

    resources = [
      "arn:aws:s3:::${var.name_prefix}-*"
    ]
  }

  statement {
    sid    = "ReadWriteProjectFallbackBucketObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [
      "arn:aws:s3:::${var.name_prefix}-*/*"
    ]
  }

  statement {
    sid    = "EcrLogin"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "CreateEcrRepositoryFallback"
    effect = "Allow"

    actions = [
      "ecr:CreateRepository"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "UseProjectEcrRepository"
    effect = "Allow"

    actions = [
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]

    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.name_prefix}"
    ]
  }

  statement {
    sid    = "EksDescribeCluster"
    effect = "Allow"

    actions = [
      "eks:DescribeCluster",
      "eks:ListClusters"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "jenkins_inline" {
  name   = "${var.name_prefix}-${var.environment}-jenkins-policy"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.jenkins_inline.json
}

resource "aws_eks_access_entry" "jenkins" {
  cluster_name  = data.aws_ssm_parameter.eks_cluster_name.value
  principal_arn = aws_iam_role.jenkins.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "jenkins_cluster_admin" {
  cluster_name  = data.aws_ssm_parameter.eks_cluster_name.value
  principal_arn = aws_iam_role.jenkins.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.jenkins
  ]
}