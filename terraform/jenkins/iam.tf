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
    sid    = "EcrPushPull"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages"
    ]

    resources = ["*"]
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

  statement {
    sid    = "ReadWriteAppBucketForPipelineChecks"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${data.aws_ssm_parameter.app_bucket_name.value}"
    ]
  }

  statement {
    sid    = "ReadWriteAppBucketObjectsForPipelineChecks"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [
      "arn:aws:s3:::${data.aws_ssm_parameter.app_bucket_name.value}/*"
    ]
  }
}

resource "aws_iam_role_policy" "jenkins_inline" {
  name   = "${var.name_prefix}-${var.environment}-jenkins-policy"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.jenkins_inline.json
}