terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "jenkins" {
  name_prefix = "${var.name_prefix}-jenkins-"
  description = "Private Jenkins controller. No inbound access; use SSM port forwarding."
  vpc_id      = local.vpc_id

  egress {
    description = "All outbound via NAT/VPC endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.name_prefix}-jenkins-sg"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = local.jenkins_subnet_id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  key_name                    = var.ssh_key_name != "" ? var.ssh_key_name : null

  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = false

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  lifecycle {
    ignore_changes = [
      ami,
      user_data
    ]
  }

  tags = {
    Name        = "${var.name_prefix}-jenkins"
    Role        = "jenkins-controller"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}