#!/bin/bash

# Build Docker Images for Minikube Deployment
# This script builds all required Docker images for the image processing pipeline

set -e

echo "🔨 Building Docker Images for Minikube"
echo "====================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Image names and tags
IMAGE_PREFIX="image-pipeline"
API_IMAGE="${IMAGE_PREFIX}-api:latest"
WORKER_IMAGE="${IMAGE_PREFIX}-worker:latest"
STATUS_IMAGE="${IMAGE_PREFIX}-status:latest"

# Function to build image
build_image() {
    local service_name=$1
    local dockerfile_path=$2
    local image_name=$3
    
    echo -e "\n${BLUE}Building $service_name...${NC}"
    echo "Dockerfile: $dockerfile_path"
    echo "Image: $image_name"
    
    # Build the image
    docker build -f "$dockerfile_path" -t "$image_name" .
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $service_name built successfully${NC}"
    else
        echo -e "${RED}❌ Failed to build $service_name${NC}"
        exit 1
    fi
}

# Check if we're in the right directory
if [ ! -f "go.mod" ]; then
    echo -e "${RED}❌ Please run this script from the project root directory${NC}"
    exit 1
fi

# Check if Minikube is running
if ! minikube status | grep -q "Running"; then
    echo -e "${RED}❌ Minikube is not running. Please start Minikube first:${NC}"
    echo "  minikube start"
    exit 1
fi

# Configure Docker to use Minikube's daemon
echo -e "${YELLOW}Configuring Docker environment for Minikube...${NC}"
eval $(minikube docker-env)

echo -e "\n${BLUE}Building Images${NC}"
echo "---------------"

# Build API service
build_image "API Service" "services/api/Dockerfile" "$API_IMAGE"

# Build Worker service
build_image "Worker Service" "services/worker/Dockerfile" "$WORKER_IMAGE"

# Build Status service
build_image "Status Service" "services/status/Dockerfile" "$STATUS_IMAGE"

echo -e "\n${BLUE}Image Summary${NC}"
echo "-------------"

# List built images
echo "Built images:"
docker images | grep "$IMAGE_PREFIX"

echo -e "\n${GREEN}🎉 All images built successfully!${NC}"
echo ""
echo "Next steps:"
echo "1. Deploy infrastructure: ./deploy/deploy-infrastructure.sh"
echo "2. Deploy application: ./deploy/deploy-application.sh"
