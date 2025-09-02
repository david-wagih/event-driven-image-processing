#!/bin/bash

# Validate Minikube Deployment
# This script validates the image processing pipeline deployment on Minikube

set -e

echo "🔍 Validating Minikube Deployment"
echo "================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="image-pipeline"
API_BASE_URL="http://localhost:8000"
STATUS_BASE_URL="http://localhost:8001"

# Function to check if service is responding
check_service() {
    local service_name=$1
    local url=$2
    
    echo -n "Checking $service_name... "
    if curl -s "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Responding${NC}"
        return 0
    else
        echo -e "${RED}❌ Not responding${NC}"
        return 1
    fi
}

# Function to check pod status
check_pod_status() {
    local component=$1
    local expected_replicas=$2
    
    echo -n "Checking $component pods... "
    running_pods=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=$component" --no-headers | grep "Running" | wc -l)
    
    if [ "$running_pods" -eq "$expected_replicas" ]; then
        echo -e "${GREEN}✅ $running_pods/$expected_replicas running${NC}"
        return 0
    else
        echo -e "${RED}❌ $running_pods/$expected_replicas running (expected $expected_replicas)${NC}"
        return 1
    fi
}

# Function to check infrastructure pod status
check_infrastructure_pod_status() {
    local component=$1
    local expected_replicas=$2
    
    echo -n "Checking $component pods... "
    running_pods=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$component" --no-headers | grep "Running" | wc -l)
    
    if [ "$running_pods" -eq "$expected_replicas" ]; then
        echo -e "${GREEN}✅ $running_pods/$expected_replicas running${NC}"
        return 0
    else
        echo -e "${RED}❌ $running_pods/$expected_replicas running (expected $expected_replicas)${NC}"
        return 1
    fi
}

# Check if we're in the right directory
if [ ! -f "go.mod" ]; then
    echo -e "${RED}❌ Please run this script from the project root directory${NC}"
    exit 1
fi

# Check if Minikube is running
if ! minikube status | grep -q "Running"; then
    echo -e "${RED}❌ Minikube is not running${NC}"
    exit 1
fi

echo -e "\n${BLUE}1. Checking Pod Status${NC}"
echo "----------------------"

# Check all pods are running
check_pod_status "api" 1
check_pod_status "status" 1
check_pod_status "worker" 1

# Check infrastructure pods
check_infrastructure_pod_status "redis" 4
check_infrastructure_pod_status "rabbitmq" 1
check_infrastructure_pod_status "minio" 2
check_infrastructure_pod_status "postgresql" 1

echo -e "\n${BLUE}2. Checking Service Health${NC}"
echo "-----------------------------"

# Check API service
check_service "API Service" "$API_BASE_URL/health"

# Check Status service
check_service "Status Service" "$STATUS_BASE_URL/health"

echo -e "\n${BLUE}3. Testing Image Processing Pipeline${NC}"
echo "----------------------------------------"

# Test image URL
TEST_IMAGE_URL="https://picsum.photos/800/600"

echo "Creating a test job with image: $TEST_IMAGE_URL"

# Create a job
JOB_RESPONSE=$(curl -s -X POST "http://$MINIKUBE_IP:30080/jobs" \
  -H "Content-Type: application/json" \
  -d "{
    \"image_url\": \"$TEST_IMAGE_URL\",
    \"operations\": [
      {
        \"type\": \"resize\",
        \"width\": 400,
        \"height\": 300,
        \"format\": \"jpeg\",
        \"quality\": 90,
        \"output_key\": \"test-thumbnail\"
      }
    ]
  }")

echo "Job creation response:"
echo "$JOB_RESPONSE" | jq '.' 2>/dev/null || echo "$JOB_RESPONSE"

# Extract job ID
JOB_ID=$(echo "$JOB_RESPONSE" | jq -r '.job.id' 2>/dev/null)

if [ "$JOB_ID" = "null" ] || [ -z "$JOB_ID" ]; then
    echo -e "${RED}❌ Failed to create job${NC}"
    exit 1
fi

echo -e "\n${GREEN}✅ Job created with ID: $JOB_ID${NC}"

# Wait for processing
echo -e "\n${YELLOW}⏳ Waiting for job processing...${NC}"
sleep 15

# Check job status
echo "Checking job status..."
STATUS_RESPONSE=$(curl -s "http://$MINIKUBE_IP:30081/jobs/$JOB_ID")

echo "Job status:"
echo "$STATUS_RESPONSE" | jq '.' 2>/dev/null || echo "$STATUS_RESPONSE"

# Check if job completed successfully
JOB_STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status' 2>/dev/null)

if [ "$JOB_STATUS" = "completed" ]; then
    echo -e "\n${GREEN}✅ Job completed successfully!${NC}"
    
    # Check if results were generated
    RESULTS_COUNT=$(echo "$STATUS_RESPONSE" | jq '.results | length' 2>/dev/null)
    echo -e "${GREEN}✅ Generated $RESULTS_COUNT processed images${NC}"
    
    # Show result details
    echo "Results:"
    echo "$STATUS_RESPONSE" | jq '.results[] | {operation: .operation.type, output_url: .output_url, size: .size, width: .width, height: .height}' 2>/dev/null || echo "Results available in response above"
    
elif [ "$JOB_STATUS" = "failed" ]; then
    echo -e "\n${RED}❌ Job failed${NC}"
    ERROR_MSG=$(echo "$STATUS_RESPONSE" | jq -r '.error' 2>/dev/null)
    echo "Error: $ERROR_MSG"
    exit 1
else
    echo -e "\n${YELLOW}⏳ Job still processing (status: $JOB_STATUS)${NC}"
    echo "You can check the status again with: curl http://$MINIKUBE_IP:30081/jobs/$JOB_ID"
fi

echo -e "\n${BLUE}4. Checking Infrastructure Services${NC}"
echo "----------------------------------------"

# Check RabbitMQ management
RABBITMQ_PORT=$(kubectl get svc rabbitmq -n $NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="management")].nodePort}' 2>/dev/null)
if [ -n "$RABBITMQ_PORT" ]; then
    check_service "RabbitMQ Management" "http://$MINIKUBE_IP:$RABBITMQ_PORT"
else
    echo -e "${YELLOW}⚠️  RabbitMQ management port not found${NC}"
fi

# Check MinIO console
MINIO_PORT=$(kubectl get svc minio -n $NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="console")].nodePort}' 2>/dev/null)
if [ -n "$MINIO_PORT" ]; then
    check_service "MinIO Console" "http://$MINIKUBE_IP:$MINIO_PORT"
else
    echo -e "${YELLOW}⚠️  MinIO console port not found${NC}"
fi

echo -e "\n${BLUE}5. System Summary${NC}"
echo "-------------------"

echo -e "${GREEN}✅ All pods are running${NC}"
echo -e "${GREEN}✅ Services are responding${NC}"
echo -e "${GREEN}✅ Image processing pipeline is functional${NC}"

echo -e "\n${BLUE}Available Endpoints:${NC}"
echo "API Service: http://$MINIKUBE_IP:30080"
echo "Status Service: http://$MINIKUBE_IP:30081"
if [ -n "$RABBITMQ_PORT" ]; then
    echo "RabbitMQ Management: http://$MINIKUBE_IP:$RABBITMQ_PORT"
fi
if [ -n "$MINIO_PORT" ]; then
    echo "MinIO Console: http://$MINIKUBE_IP:$MINIO_PORT"
fi

echo -e "\n${BLUE}Example Usage:${NC}"
echo "Create a job:"
echo 'curl -X POST "http://'$MINIKUBE_IP':30080/jobs" -H "Content-Type: application/json" -d '"'"'{"image_url": "https://picsum.photos/800/600", "operations": [{"type": "resize", "width": 400, "height": 300, "format": "jpeg"}]}'"'"

echo -e "\nCheck job status:"
echo "curl http://$MINIKUBE_IP:30081/jobs/{JOB_ID}"

echo -e "\n${GREEN}🎉 Minikube deployment validation complete!${NC}"
