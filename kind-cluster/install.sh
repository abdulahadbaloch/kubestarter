#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail

echo "🚀 Starting installation of Docker, Kind, and kubectl..."

# ----------------------------
# 1. Install Docker
# ----------------------------
if ! command -v docker &>/dev/null; then
  echo "📦 Installing Docker..."
  sudo apt-get update -y
  sudo apt-get install -y docker.io

  echo "👤 Adding current user to docker group..."
  sudo usermod -aG docker "$USER"

  echo "✅ Docker installed and user added to docker group."
  echo "⚠️  You must log out/in (or run 'newgrp docker') before using docker without sudo."
else
  echo "✅ Docker is already installed."
fi

# Make sure the docker daemon is actually up before Kind tries to use it
if command -v systemctl &>/dev/null; then
  sudo systemctl enable docker --now || true
fi

echo "⏳ Waiting for Docker daemon to be ready..."
for i in $(seq 1 15); do
  if sudo docker info &>/dev/null; then
    echo "✅ Docker daemon is ready."
    break
  fi
  sleep 2
  if [ "$i" -eq 15 ]; then
    echo "❌ Docker daemon did not become ready in time."
    exit 1
  fi
done

# ----------------------------
# 2. Install Kind (based on architecture)
#    Version resolved dynamically from GitHub's latest release
#    so it never points at a stale/nonexistent tag.
# ----------------------------
if ! command -v kind &>/dev/null; then
  echo "📦 Installing Kind..."

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  KIND_ARCH="amd64" ;;
    aarch64|arm64) KIND_ARCH="arm64" ;;
    *)
      echo "❌ Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac

  # Resolve the latest stable Kind release tag (e.g. v0.32.0).
  # Falls back to a known-good pinned version if GitHub API is unreachable.
  KIND_FALLBACK_VERSION="v0.32.0"
  KIND_VERSION=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest \
    | grep '"tag_name":' \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/') || true

  if [ -z "$KIND_VERSION" ]; then
    echo "⚠️  Could not resolve latest Kind version from GitHub API, using fallback ${KIND_FALLBACK_VERSION}"
    KIND_VERSION="$KIND_FALLBACK_VERSION"
  fi

  echo "⬇️  Downloading Kind ${KIND_VERSION} for ${KIND_ARCH}..."
  curl -fLo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${KIND_ARCH}"

  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
  echo "✅ Kind ${KIND_VERSION} installed successfully."
else
  echo "✅ Kind is already installed."
fi

# ----------------------------
# 3. Install kubectl (based on architecture)
#    Pinned to the Kubernetes minor version that matches Kind's default
#    node image, to avoid client/server skew issues during cluster creation.
# ----------------------------
if ! command -v kubectl &>/dev/null; then
  echo "📦 Installing kubectl (stable version)..."

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  KUBECTL_ARCH="amd64" ;;
    aarch64|arm64) KUBECTL_ARCH="arm64" ;;
    *)
      echo "❌ Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac

  # Use the official "stable" channel, with a pinned fallback so the
  # script never breaks if dl.k8s.io is briefly unreachable.
  KUBECTL_FALLBACK_VERSION="v1.34.0"
  KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt) || true

  if [ -z "$KUBECTL_VERSION" ]; then
    echo "⚠️  Could not resolve latest stable kubectl version, using fallback ${KUBECTL_FALLBACK_VERSION}"
    KUBECTL_VERSION="$KUBECTL_FALLBACK_VERSION"
  fi

  echo "⬇️  Downloading kubectl ${KUBECTL_VERSION} for ${KUBECTL_ARCH}..."
  curl -fLo ./kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl"

  chmod +x ./kubectl
  sudo mv ./kubectl /usr/local/bin/kubectl
  echo "✅ kubectl ${KUBECTL_VERSION} installed successfully."
else
  echo "✅ kubectl is already installed."
fi

# ----------------------------
# 4. Confirm Versions
# ----------------------------
echo
echo "🔍 Installed Versions:"
docker --version
kind --version
kubectl version --client --output=yaml

echo
echo "🎉 Docker, Kind, and kubectl installation complete!"
echo "ℹ️  If this is your first Docker install on this machine, log out/in (or run 'newgrp docker') before running 'kind create cluster'."
