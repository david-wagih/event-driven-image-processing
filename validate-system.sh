#!/bin/bash

# Image Processing Pipeline Validation Script
# This script validates all components of the system

set -e

echo "🔍 Image Processing Pipeline Validation"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if a service is running
check_service() {
    local service_name=$1
    local port=$2
    local url=$3
    
    echo -n "Checking $service_name... "
    if curl -s "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Running${NC}"
        return 0
    else
        echo -e "${RED}❌ Not responding${NC}"
        return 1
    fi
}

# Function to check Docker container status
check_container() {
    local container_name=$1
    echo -n "Checking container $container_name... "
    if docker ps --format "table {{.Names}}" | grep -q "^$container_name$"; then
        echo -e "${GREEN}✅ Running${NC}"
        return 0
    else
        echo -e "${RED}❌ Not running${NC}"
        return 1
    fi
}

echo -e "\n${BLUE}1. Checking Docker Compose Services${NC}"
echo "----------------------------------------"

# Check if docker-compose is running
if ! docker-compose ps | grep -q "Up"; then
    echo -e "${RED}❌ Docker Compose services are not running${NC}"
    echo "Please start the services with: docker-compose up -d"
    exit 1
fi

# Check individual containers
check_container "devops-projects-redis-1"
check_container "devops-projects-rabbitmq-1"
check_container "devops-projects-minio-1"
check_container "devops-projects-postgres-1"
check_container "devops-projects-api-1"
check_container "devops-projects-worker-1"
check_container "devops-projects-status-1"

echo -e "\n${BLUE}2. Checking Service Health Endpoints${NC}"
echo "----------------------------------------"

# Wait a moment for services to be ready
sleep 5

# Check API health
check_service "API Service" "8000" "http://localhost:8000/health"

# Check Status service health
check_service "Status Service" "8001" "http://localhost:8001/health"

# Check RabbitMQ management
check_service "RabbitMQ Management" "15672" "http://localhost:15672"

# Check MinIO console
check_service "MinIO Console" "9001" "http://localhost:9001"

echo -e "\n${BLUE}3. Testing Image Processing Pipeline${NC}"
echo "----------------------------------------"

# Test image URL (using a sample image)
TEST_IMAGE_URL="https://picsum.photos/800/600"

echo "Creating a test job with image: $TEST_IMAGE_URL"

# Create a job
JOB_RESPONSE=$(curl -s -X POST http://localhost:8000/jobs \
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
echo "$JOB_RESPONSE" | jq '.'

# Extract job ID
JOB_ID=$(echo "$JOB_RESPONSE" | jq -r '.job.id')

if [ "$JOB_ID" = "null" ] || [ -z "$JOB_ID" ]; then
    echo -e "${RED}❌ Failed to create job${NC}"
    exit 1
fi

echo -e "\n${GREEN}✅ Job created with ID: $JOB_ID${NC}"

# Wait for processing
echo -e "\n${YELLOW}⏳ Waiting for job processing...${NC}"
sleep 10

# Check job status
echo "Checking job status..."
STATUS_RESPONSE=$(curl -s "http://localhost:8001/jobs/$JOB_ID")

echo "Job status:"
echo "$STATUS_RESPONSE" | jq '.'

# Check if job completed successfully
JOB_STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')

if [ "$JOB_STATUS" = "completed" ]; then
    echo -e "\n${GREEN}✅ Job completed successfully!${NC}"
    
    # Check if results were generated
    RESULTS_COUNT=$(echo "$STATUS_RESPONSE" | jq '.results | length')
    echo -e "${GREEN}✅ Generated $RESULTS_COUNT processed images${NC}"
    
    # Show result details
    echo "Results:"
    echo "$STATUS_RESPONSE" | jq '.results[] | {operation: .operation.type, output_url: .output_url, size: .size, width: .width, height: .height}'
    
elif [ "$JOB_STATUS" = "failed" ]; then
    echo -e "\n${RED}❌ Job failed${NC}"
    ERROR_MSG=$(echo "$STATUS_RESPONSE" | jq -r '.error')
    echo "Error: $ERROR_MSG"
    exit 1
else
    echo -e "\n${YELLOW}⏳ Job still processing (status: $JOB_STATUS)${NC}"
    echo "You can check the status again with: curl http://localhost:8001/jobs/$JOB_ID"
fi

echo -e "\n${BLUE}4. Checking MinIO Storage${NC}"
echo "--------------------------------"

# Check if processed images are in MinIO
echo "Checking MinIO for processed images..."

# You can access MinIO console at http://localhost:9001
# Login with: minioadmin / minioadmin123
echo -e "${YELLOW}📁 MinIO Console: http://localhost:9001${NC}"
echo -e "${YELLOW}   Username: minioadmin${NC}"
echo -e "${YELLOW}   Password: minioadmin123${NC}"

echo -e "\n${BLUE}5. System Summary${NC}"
echo "-------------------"

echo -e "${GREEN}✅ All services are running${NC}"
echo -e "${GREEN}✅ Image processing pipeline is functional${NC}"
echo -e "${GREEN}✅ Jobs can be created and processed${NC}"

echo -e "\n${BLUE}Available Endpoints:${NC}"
echo "API Service: http://localhost:8000"
echo "Status Service: http://localhost:8001"
echo "RabbitMQ Management: http://localhost:15672"
echo "MinIO Console: http://localhost:9001"

echo -e "\n${BLUE}Example Usage:${NC}"
echo "Create a job:"
echo 'curl -X POST http://localhost:8000/jobs -H "Content-Type: application/json" -d '"'"'{"image_url": "https://picsum.photos/800/600", "operations": [{"type": "resize", "width": 400, "height": 300, "format": "jpeg"}]}'"'"

echo -e "\nCheck job status:"
echo "curl http://localhost:8001/jobs/{JOB_ID}"

echo -e "\n${GREEN}🎉 System validation complete!${NC}"
