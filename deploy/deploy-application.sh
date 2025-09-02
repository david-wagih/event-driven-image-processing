#!/bin/bash

# Deploy Application Services to Minikube
# This script deploys the image processing pipeline application using Helm

set -e

echo "🚀 Deploying Application Services to Minikube"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="image-pipeline"
RELEASE_NAME="image-pipeline"
CHART_PATH="deploy/helm"

# Function to check if service is ready
check_service_ready() {
    local service_name=$1
    local max_attempts=30
    local attempt=1
    
    echo -n "Waiting for $service_name to be ready... "
    
    while [ $attempt -le $max_attempts ]; do
        if kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=$service_name" | grep -q "Running"; then
            echo -e "${GREEN}✅ Ready${NC}"
            return 0
        fi
        
        echo -n "."
        sleep 5
        ((attempt++))
    done
    
    echo -e "${RED}❌ Timeout${NC}"
    return 1
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

# Check if kubectl is configured
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}❌ kubectl is not configured. Please check your Kubernetes context.${NC}"
    exit 1
fi

# Check if infrastructure is deployed
echo -e "\n${BLUE}Checking Infrastructure Services${NC}"
echo "-----------------------------------"

if ! kubectl get pods -n "$NAMESPACE" | grep -q "redis-master"; then
    echo -e "${RED}❌ Redis is not deployed. Please deploy infrastructure first:${NC}"
    echo "  ./deploy/deploy-infrastructure.sh"
    exit 1
fi

if ! kubectl get pods -n "$NAMESPACE" | grep -q "rabbitmq"; then
    echo -e "${RED}❌ RabbitMQ is not deployed. Please deploy infrastructure first:${NC}"
    echo "  ./deploy/deploy-infrastructure.sh"
    exit 1
fi

if ! kubectl get pods -n "$NAMESPACE" | grep -q "minio"; then
    echo -e "${RED}❌ MinIO is not deployed. Please deploy infrastructure first:${NC}"
    echo "  ./deploy/deploy-infrastructure.sh"
    exit 1
fi

echo -e "${GREEN}✅ Infrastructure services are running${NC}"

# Configure Docker environment
echo -e "\n${BLUE}Configuring Docker Environment${NC}"
echo "-----------------------------------"
eval $(minikube docker-env)

# Check if images are built
echo -e "\n${BLUE}Checking Docker Images${NC}"
echo "---------------------------"

if ! docker images | grep -q "image-pipeline-api"; then
    echo -e "${RED}❌ API image not found. Please build images first:${NC}"
    echo "  ./deploy/build-images.sh"
    exit 1
fi

if ! docker images | grep -q "image-pipeline-worker"; then
    echo -e "${RED}❌ Worker image not found. Please build images first:${NC}"
    echo "  ./deploy/build-images.sh"
    exit 1
fi

if ! docker images | grep -q "image-pipeline-status"; then
    echo -e "${RED}❌ Status image not found. Please build images first:${NC}"
    echo "  ./deploy/build-images.sh"
    exit 1
fi

echo -e "${GREEN}✅ All required images are available${NC}"

# Deploy application using Helm
echo -e "\n${BLUE}Deploying Application Services${NC}"
echo "-----------------------------------"

echo "Deploying with Helm..."
helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --timeout=30m

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Application deployed successfully${NC}"
else
    echo -e "${RED}❌ Failed to deploy application${NC}"
    exit 1
fi

# Wait for services to be ready
echo -e "\n${BLUE}Waiting for Services to be Ready${NC}"
echo "-------------------------------------"

check_service_ready "api"
check_service_ready "status"
check_service_ready "worker"

# Get service information
echo -e "\n${BLUE}Service Information${NC}"
echo "---------------------"

MINIKUBE_IP=$(minikube ip)

echo "API Service:"
echo "  URL: http://$MINIKUBE_IP:30080"
echo "  Health: http://$MINIKUBE_IP:30080/health"

echo -e "\nStatus Service:"
echo "  URL: http://$MINIKUBE_IP:30081"
echo "  Health: http://$MINIKUBE_IP:30081/health"

echo -e "\nInfrastructure Services:"
echo "  RabbitMQ Management: http://$MINIKUBE_IP:$(kubectl get svc rabbitmq -n $NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="management")].nodePort}')"
echo "  MinIO Console: http://$MINIKUBE_IP:$(kubectl get svc minio -n $NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="console")].nodePort}')"

echo -e "\n${BLUE}Pod Status${NC}"
echo "----------"
kubectl get pods -n "$NAMESPACE" -o wide

echo -e "\n${BLUE}Service Status${NC}"
echo "----------------"
kubectl get svc -n "$NAMESPACE"

echo -e "\n${GREEN}🎉 Application deployment complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Test the API: curl http://$MINIKUBE_IP:30080/health"
echo "2. Create a job: curl -X POST http://$MINIKUBE_IP:30080/jobs -H 'Content-Type: application/json' -d '{\"image_url\": \"https://picsum.photos/800/600\", \"operations\": [{\"type\": \"resize\", \"width\": 400, \"height\": 300, \"format\": \"jpeg\"}]}'"
echo "3. Validate deployment: ./deploy/validate-deployment.sh"
