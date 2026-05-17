#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

LOG_FILE="/var/log/jenkins-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "==> Jenkins bootstrap started at $(date -Iseconds)"

apt-get update -y

apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  unzip \
  jq \
  git \
  apt-transport-https \
  software-properties-common \
  fontconfig \
  openjdk-21-jre \
  python3 \
  python3-pip \
  python3-venv \

echo "==> Installing Jenkins"

install -m 0755 -d /etc/apt/keyrings

rm -f /etc/apt/sources.list.d/jenkins.list
rm -f /etc/apt/keyrings/jenkins-keyring.asc

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc

chmod 0644 /etc/apt/keyrings/jenkins-keyring.asc

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y
apt-get install -y jenkins

systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

echo "==> Installing Docker"

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

usermod -aG docker jenkins
usermod -aG docker ubuntu || true

echo "==> Installing AWS CLI v2"

TMP_DIR="$(mktemp -d)"
cd "$TMP_DIR"

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install --update

cd /
rm -rf "$TMP_DIR"

echo "==> Installing kubectl"

KUBECTL_VERSION="v1.32.0"
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  -o /usr/local/bin/kubectl

chmod +x /usr/local/bin/kubectl

echo "==> Installing Helm"

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "==> Writing bootstrap verification file"

cat > /opt/jenkins-bootstrap-info.txt <<EOF
Jenkins bootstrap completed at $(date -Iseconds)

Installed tools:
$(java -version 2>&1 | head -n 1 || true)
$(jenkins --version 2>/dev/null || true)
$(docker --version || true)
$(aws --version || true)
$(kubectl version --client=true 2>/dev/null || true)
$(helm version --short 2>/dev/null || true)

Logs:
$LOG_FILE
EOF

chown root:root /opt/jenkins-bootstrap-info.txt
chmod 0644 /opt/jenkins-bootstrap-info.txt

systemctl restart jenkins

echo "==> Jenkins bootstrap finished at $(date -Iseconds)"