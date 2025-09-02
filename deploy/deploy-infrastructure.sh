#!/bin/bash

# Deploy Infrastructure Services to Minikube
# This script deploys Redis, RabbitMQ, MinIO, and PostgreSQL using Helm charts

set -e

echo "🏗️  Deploying Infrastructure Services to Minikube"
echo "================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Namespace
NAMESPACE="image-pipeline"

# Function to deploy service
deploy_service() {
    local service_name=$1
    local chart_name=$2
    local release_name=$3
    local values_file=$4
    
    echo -e "\n${BLUE}Deploying $service_name...${NC}"
    
    if [ -f "$values_file" ]; then
        echo "Using custom values: $values_file"
        helm upgrade --install "$release_name" "bitnami/$chart_name" \
            --namespace "$NAMESPACE" \
            --create-namespace \
            --values "$values_file" \
            --timeout=20m
    else
        echo "Using default values"
        helm upgrade --install "$release_name" "bitnami/$chart_name" \
            --namespace "$NAMESPACE" \
            --create-namespace \
            --timeout=20m
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $service_name deployed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to deploy $service_name${NC}"
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

# Check if kubectl is configured
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}❌ kubectl is not configured. Please check your Kubernetes context.${NC}"
    exit 1
fi

# Update Helm repositories
echo -e "${YELLOW}Updating Helm repositories...${NC}"
helm repo update

echo -e "\n${BLUE}Deploying Infrastructure Services${NC}"
echo "----------------------------------------"

# Deploy Redis
deploy_service "Redis" "redis" "redis" "deploy/helm/values-redis.yaml"

# Deploy RabbitMQ
deploy_service "RabbitMQ" "rabbitmq" "rabbitmq" "deploy/helm/values-rabbitmq.yaml"

# Deploy MinIO
deploy_service "MinIO" "minio" "minio" "deploy/helm/values-minio.yaml"

# Deploy PostgreSQL
deploy_service "PostgreSQL" "postgresql" "postgresql" "deploy/helm/values-postgresql.yaml"

echo -e "\n${BLUE}Waiting for all services to be ready...${NC}"
echo "--------------------------------------------"

# Wait for all deployments to be ready
echo "Waiting for Redis to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/redis-master -n "$NAMESPACE"

echo "Waiting for RabbitMQ to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/rabbitmq -n "$NAMESPACE"

echo "Waiting for MinIO to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/minio -n "$NAMESPACE"

echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/postgresql -n "$NAMESPACE"

echo -e "\n${BLUE}Service Information${NC}"
echo "---------------------"

# Get service URLs and credentials
echo "Redis:"
echo "  Service: redis-master.$NAMESPACE.svc.cluster.local:6379"
echo "  Password: $(kubectl get secret redis -n $NAMESPACE -o jsonpath='{.data.redis-password}' | base64 -d)"

echo -e "\nRabbitMQ:"
echo "  Service: rabbitmq.$NAMESPACE.svc.cluster.local:5672"
echo "  Management: http://$(minikube ip):$(kubectl get svc rabbitmq -n $NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="management")].nodePort}')"
echo "  Username: user"
echo "  Password: $(kubectl get secret rabbitmq -n $NAMESPACE -o jsonpath='{.data.rabbitmq-password}' | base64 -d)"

echo -e "\nMinIO:"
echo "  Service: minio.$NAMESPACE.svc.cluster.local:9000"
echo "  Console: http://$(minikube ip):$(kubectl get svc minio -n $NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="console")].nodePort}')"
echo "  Access Key: minioadmin"
echo "  Secret Key: minioadmin123"

echo -e "\nPostgreSQL:"
echo "  Service: postgresql.$NAMESPACE.svc.cluster.local:5432"
echo "  Database: jobsdb"
echo "  Username: davidwagih"
echo "  Password: $(kubectl get secret postgresql -n $NAMESPACE -o jsonpath='{.data.postgres-password}' | base64 -d)"

echo -e "\n${GREEN}🎉 Infrastructure deployment complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Deploy application: ./deploy/deploy-application.sh"
echo "2. Validate deployment: ./deploy/validate-deployment.sh"
