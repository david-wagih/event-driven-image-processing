#!/bin/bash

# Wait for Infrastructure Services to be Ready
# This script waits for all infrastructure services to be ready after deployment

set -e

echo "⏳ Waiting for Infrastructure Services to be Ready"
echo "================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Namespace
NAMESPACE="image-pipeline"

# Function to wait for deployment
wait_for_deployment() {
    local deployment_name=$1
    local max_attempts=60  # 10 minutes with 10-second intervals
    local attempt=1
    
    echo -n "Waiting for $deployment_name... "
    
    while [ $attempt -le $max_attempts ]; do
        if kubectl get deployment "$deployment_name" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q "1"; then
            echo -e "${GREEN}✅ Ready${NC}"
            return 0
        fi
        
        echo -n "."
        sleep 10
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

echo -e "\n${BLUE}Checking Service Status${NC}"
echo "------------------------"

# Wait for Redis
wait_for_deployment "redis-master"

# Wait for RabbitMQ
wait_for_deployment "rabbitmq"

# Wait for MinIO
wait_for_deployment "minio"

# Wait for PostgreSQL
wait_for_deployment "postgresql"

echo -e "\n${BLUE}Service Information${NC}"
echo "---------------------"

# Get service URLs and credentials
echo "Redis:"
echo "  Service: redis-master.$NAMESPACE.svc.cluster.local:6379"
echo "  Password: $(kubectl get secret redis -n $NAMESPACE -o jsonpath='{.data.redis-password}' | base64 -d 2>/dev/null || echo "Not available yet")"

echo -e "\nRabbitMQ:"
echo "  Service: rabbitmq.$NAMESPACE.svc.cluster.local:5672"
RABBITMQ_PORT=$(kubectl get svc rabbitmq -n $NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="management")].nodePort}' 2>/dev/null)
if [ -n "$RABBITMQ_PORT" ]; then
    echo "  Management: http://$(minikube ip):$RABBITMQ_PORT"
fi
echo "  Username: user"
echo "  Password: $(kubectl get secret rabbitmq -n $NAMESPACE -o jsonpath='{.data.rabbitmq-password}' | base64 -d 2>/dev/null || echo "Not available yet")"

echo -e "\nMinIO:"
echo "  Service: minio.$NAMESPACE.svc.cluster.local:9000"
MINIO_PORT=$(kubectl get svc minio -n $NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="console")].nodePort}' 2>/dev/null)
if [ -n "$MINIO_PORT" ]; then
    echo "  Console: http://$(minikube ip):$MINIO_PORT"
fi
echo "  Access Key: minioadmin"
echo "  Secret Key: minioadmin123"

echo -e "\nPostgreSQL:"
echo "  Service: postgresql.$NAMESPACE.svc.cluster.local:5432"
echo "  Database: jobsdb"
echo "  Username: davidwagih"
echo "  Password: $(kubectl get secret postgresql -n $NAMESPACE -o jsonpath='{.data.postgres-password}' | base64 -d 2>/dev/null || echo "Not available yet")"

echo -e "\n${GREEN}🎉 All services are ready!${NC}"
echo ""
echo "Next steps:"
echo "1. Deploy application: ./deploy/deploy-application.sh"
echo "2. Validate deployment: ./deploy/validate-deployment.sh"
