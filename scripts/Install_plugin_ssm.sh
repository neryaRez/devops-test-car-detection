#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking AWS Session Manager Plugin"

if command -v session-manager-plugin >/dev/null 2>&1; then
  echo "✅ Session Manager Plugin is already installed."
  session-manager-plugin || true
  exit 0
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

if [[ "$OS" != "Linux" ]]; then
  echo "❌ This installer currently supports Linux only."
  echo "Please install the AWS Session Manager Plugin manually for your OS:"
  echo "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
  exit 1
fi

case "$ARCH" in
  x86_64|amd64)
    PLUGIN_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
    ;;
  aarch64|arm64)
    PLUGIN_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb"
    ;;
  *)
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

if ! command -v dpkg >/dev/null 2>&1; then
  echo "❌ dpkg was not found. This script is intended for Ubuntu/Debian-based systems."
  echo "Please install the Session Manager Plugin manually for your distribution."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Downloading Session Manager Plugin"
curl -fsSL "$PLUGIN_URL" -o "$TMP_DIR/session-manager-plugin.deb"

echo "==> Installing Session Manager Plugin"
sudo dpkg -i "$TMP_DIR/session-manager-plugin.deb"

echo "==> Verifying installation"
if command -v session-manager-plugin >/dev/null 2>&1; then
  echo "✅ Session Manager Plugin installed successfully."
  session-manager-plugin || true
else
  echo "❌ Installation finished, but session-manager-plugin was not found in PATH."
  exit 1
fi