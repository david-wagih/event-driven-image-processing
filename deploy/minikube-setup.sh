#!/bin/bash

# Minikube Setup Script for Image Processing Pipeline
# This script prepares Minikube for deploying the image processing pipeline

set -e

echo "🚀 Setting up Minikube for Image Processing Pipeline"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if Minikube is running
check_minikube_status() {
    if minikube status | grep -q "Running"; then
        return 0
    else
        return 1
    fi
}

echo -e "\n${BLUE}1. Checking Prerequisites${NC}"
echo "---------------------------"

# Check if required tools are installed
echo -n "Checking kubectl... "
if command_exists kubectl; then
    echo -e "${GREEN}✅ Installed${NC}"
else
    echo -e "${RED}❌ Not found${NC}"
    echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

echo -n "Checking minikube... "
if command_exists minikube; then
    echo -e "${GREEN}✅ Installed${NC}"
else
    echo -e "${RED}❌ Not found${NC}"
    echo "Please install minikube: https://minikube.sigs.k8s.io/docs/start/"
    exit 1
fi

echo -n "Checking helm... "
if command_exists helm; then
    echo -e "${GREEN}✅ Installed${NC}"
else
    echo -e "${RED}❌ Not found${NC}"
    echo "Please install helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo -n "Checking docker... "
if command_exists docker; then
    echo -e "${GREEN}✅ Installed${NC}"
else
    echo -e "${RED}❌ Not found${NC}"
    echo "Please install docker: https://docs.docker.com/get-docker/"
    exit 1
fi

echo -e "\n${BLUE}2. Starting Minikube Cluster${NC}"
echo "--------------------------------"

# Check if Minikube is already running
if check_minikube_status; then
    echo -e "${YELLOW}Minikube is already running${NC}"
else
    echo "Starting Minikube cluster..."
    
    # Start Minikube with resources that fit your system
    minikube start \
        --driver=docker \
        --cpus=2 \
        --memory=3072 \
        --disk-size=10g \
        --addons=ingress \
        --addons=metrics-server
    
    echo -e "${GREEN}✅ Minikube cluster started${NC}"
fi

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo -e "\n${BLUE}3. Configuring Docker Environment${NC}"
echo "----------------------------------------"

# Configure Docker to use Minikube's Docker daemon
echo "Configuring Docker to use Minikube's daemon..."
eval $(minikube docker-env)

echo -e "${GREEN}✅ Docker environment configured${NC}"

echo -e "\n${BLUE}4. Adding Helm Repositories${NC}"
echo "--------------------------------"

# Add required Helm repositories
echo "Adding Bitnami repository..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

echo -e "${GREEN}✅ Helm repositories added${NC}"

echo -e "\n${BLUE}5. Creating Namespace${NC}"
echo "---------------------------"

# Create namespace for the application
kubectl create namespace image-pipeline --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✅ Namespace 'image-pipeline' created${NC}"

echo -e "\n${BLUE}6. Cluster Information${NC}"
echo "---------------------------"

echo "Minikube IP: $(minikube ip)"
echo "Namespace: image-pipeline"
echo "Context: $(kubectl config current-context)"

echo -e "\n${BLUE}7. Next Steps${NC}"
echo "-------------"

echo "1. Build Docker images:"
echo "   ./deploy/build-images.sh"
echo ""
echo "2. Deploy infrastructure:"
echo "   ./deploy/deploy-infrastructure.sh"
echo ""
echo "3. Deploy application:"
echo "   ./deploy/deploy-application.sh"
echo ""
echo "4. Validate deployment:"
echo "   ./deploy/validate-deployment.sh"

echo -e "\n${GREEN}🎉 Minikube setup complete!${NC}"
echo ""
echo "Useful commands:"
echo "  minikube dashboard    # Open Kubernetes dashboard"
echo "  minikube tunnel       # Enable LoadBalancer services"
echo "  kubectl get pods -n image-pipeline"
