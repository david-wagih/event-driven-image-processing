# 🚀 Minikube Deployment Guide

This guide will walk you through deploying the Image Processing Pipeline to Minikube for local Kubernetes practice.

## 📋 Prerequisites

Before starting, ensure you have the following tools installed:

- **Docker** - [Install Docker](https://docs.docker.com/get-docker/)
- **Minikube** - [Install Minikube](https://minikube.sigs.k8s.io/docs/start/)
- **kubectl** - [Install kubectl](https://kubernetes.io/docs/tasks/tools/)
- **Helm** - [Install Helm](https://helm.sh/docs/intro/install/)
- **jq** (optional) - For JSON parsing in validation scripts

## 🎯 Quick Start

Run these commands in order from your project root directory:

```bash
# 1. Setup Minikube environment
./deploy/minikube-setup.sh

# 2. Build Docker images
./deploy/build-images.sh

# 3. Deploy infrastructure services
./deploy/deploy-infrastructure.sh

# 4. Deploy application services
./deploy/deploy-application.sh

# 5. Validate everything is working
./deploy/validate-deployment.sh
```

## 📖 Detailed Step-by-Step Guide

### Step 1: Setup Minikube Environment

```bash
./deploy/minikube-setup.sh
```

**What this does:**
- Checks if all required tools are installed
- Starts Minikube with adequate resources (4 CPU, 8GB RAM, 20GB disk)
- Enables ingress and metrics-server addons
- Configures Docker to use Minikube's daemon
- Adds Bitnami Helm repository
- Creates the `image-pipeline` namespace

**Expected output:**
```
🚀 Setting up Minikube for Image Processing Pipeline
==================================================

1. Checking Prerequisites
---------------------------
Checking kubectl... ✅ Installed
Checking minikube... ✅ Installed
Checking helm... ✅ Installed
Checking docker... ✅ Installed

2. Starting Minikube Cluster
--------------------------------
Starting Minikube cluster...
✅ Minikube cluster started

3. Configuring Docker Environment
----------------------------------------
✅ Docker environment configured

4. Adding Helm Repositories
--------------------------------
✅ Helm repositories added

5. Creating Namespace
---------------------------
✅ Namespace 'image-pipeline' created

🎉 Minikube setup complete!
```

### Step 2: Build Docker Images

```bash
./deploy/build-images.sh
```

**What this does:**
- Configures Docker to use Minikube's daemon
- Builds three Docker images:
  - `image-pipeline-api:latest`
  - `image-pipeline-worker:latest`
  - `image-pipeline-status:latest`

**Expected output:**
```
🔨 Building Docker Images for Minikube
=====================================

Building API Service...
Dockerfile: services/api/Dockerfile
Image: image-pipeline-api:latest
✅ API Service built successfully

Building Worker Service...
Dockerfile: services/worker/Dockerfile
Image: image-pipeline-worker:latest
✅ Worker Service built successfully

Building Status Service...
Dockerfile: services/status/Dockerfile
Image: image-pipeline-status:latest
✅ Status Service built successfully

🎉 All images built successfully!
```

### Step 3: Deploy Infrastructure Services

```bash
./deploy/deploy-infrastructure.sh
```

**What this does:**
- Deploys Redis, RabbitMQ, MinIO, and PostgreSQL using Bitnami Helm charts
- Configures each service with custom values for the image pipeline
- Waits for all services to be ready
- Displays connection information and credentials

**Expected output:**
```
🏗️  Deploying Infrastructure Services to Minikube
================================================

Deploying Redis...
✅ Redis deployed successfully

Deploying RabbitMQ...
✅ RabbitMQ deployed successfully

Deploying MinIO...
✅ MinIO deployed successfully

Deploying PostgreSQL...
✅ PostgreSQL deployed successfully

Service Information
---------------------
Redis:
  Service: redis-master.image-pipeline.svc.cluster.local:6379
  Password: [generated-password]

RabbitMQ:
  Service: rabbitmq.image-pipeline.svc.cluster.local:5672
  Management: http://192.168.49.2:3xxxx
  Username: user
  Password: [generated-password]

MinIO:
  Service: minio.image-pipeline.svc.cluster.local:9000
  Console: http://192.168.49.2:3xxxx
  Access Key: minioadmin
  Secret Key: minioadmin123

🎉 Infrastructure deployment complete!
```

### Step 4: Deploy Application Services

```bash
./deploy/deploy-application.sh
```

**What this does:**
- Deploys the API, Worker, and Status services using a custom Helm chart
- Configures environment variables to connect to infrastructure services
- Waits for all pods to be ready
- Displays service URLs and endpoints

**Expected output:**
```
🚀 Deploying Application Services to Minikube
============================================

Deploying Application Services
-----------------------------------
Deploying with Helm...
✅ Application deployed successfully

Waiting for Services to be Ready
-------------------------------------
Waiting for api to be ready... ✅ Ready
Waiting for status to be ready... ✅ Ready
Waiting for worker to be ready... ✅ Ready

Service Information
---------------------
API Service:
  URL: http://192.168.49.2:30080
  Health: http://192.168.49.2:30080/health

Status Service:
  URL: http://192.168.49.2:30081
  Health: http://192.168.49.2:30081/health

🎉 Application deployment complete!
```

### Step 5: Validate Deployment

```bash
./deploy/validate-deployment.sh
```

**What this does:**
- Checks that all pods are running
- Verifies service health endpoints
- Tests the complete image processing pipeline
- Creates a test job and validates the results
- Displays all available endpoints

**Expected output:**
```
🔍 Validating Minikube Deployment
=================================

1. Checking Pod Status
----------------------
Checking api pods... ✅ 1/1 running
Checking status pods... ✅ 1/1 running
Checking worker pods... ✅ 2/2 running

2. Checking Service Health
-----------------------------
Checking API Service... ✅ Responding
Checking Status Service... ✅ Responding

3. Testing Image Processing Pipeline
----------------------------------------
Creating a test job with image: https://picsum.photos/800/600
✅ Job created with ID: [job-id]

⏳ Waiting for job processing...
✅ Job completed successfully!
✅ Generated 1 processed images

🎉 Minikube deployment validation complete!
```

## 🌐 Accessing Your Services

Once deployed, you can access your services at:

| Service | URL | Purpose |
|---------|-----|---------|
| **API Service** | `http://[MINIKUBE_IP]:30080` | Create image processing jobs |
| **Status Service** | `http://[MINIKUBE_IP]:30081` | Check job status |
| **RabbitMQ Management** | `http://[MINIKUBE_IP]:[PORT]` | Monitor message queues |
| **MinIO Console** | `http://[MINIKUBE_IP]:[PORT]` | Browse processed images |

Replace `[MINIKUBE_IP]` with your Minikube IP (run `minikube ip` to get it).

## 🧪 Testing the Pipeline

### Create a Job

```bash
curl -X POST "http://$(minikube ip):30080/jobs" \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://picsum.photos/800/600",
    "operations": [
      {
        "type": "resize",
        "width": 400,
        "height": 300,
        "format": "jpeg",
        "quality": 90
      }
    ]
  }'
```

### Check Job Status

```bash
curl "http://$(minikube ip):30081/jobs/[JOB_ID]"
```

### Health Checks

```bash
# API health
curl "http://$(minikube ip):30080/health"

# Status service health
curl "http://$(minikube ip):30081/health"
```

## 🔧 Useful Commands

### Kubernetes Commands

```bash
# View all pods
kubectl get pods -n image-pipeline

# View services
kubectl get svc -n image-pipeline

# View logs
kubectl logs -n image-pipeline deployment/image-pipeline-api
kubectl logs -n image-pipeline deployment/image-pipeline-worker
kubectl logs -n image-pipeline deployment/image-pipeline-status

# Port forward for local access
kubectl port-forward -n image-pipeline svc/image-pipeline-api 8000:8000
```

### Minikube Commands

```bash
# Get Minikube IP
minikube ip

# Open Kubernetes dashboard
minikube dashboard

# Enable LoadBalancer services
minikube tunnel

# Stop Minikube
minikube stop

# Delete Minikube cluster
minikube delete
```

### Helm Commands

```bash
# List releases
helm list -n image-pipeline

# Upgrade release
helm upgrade image-pipeline deploy/helm -n image-pipeline

# Uninstall release
helm uninstall image-pipeline -n image-pipeline
```

## 🗑️ Cleanup

To clean up everything:

```bash
# Delete the Helm release
helm uninstall image-pipeline -n image-pipeline

# Delete infrastructure
helm uninstall redis rabbitmq minio postgresql -n image-pipeline

# Delete namespace
kubectl delete namespace image-pipeline

# Stop Minikube
minikube stop

# Optional: Delete Minikube cluster completely
minikube delete
```

## 🐛 Troubleshooting

### Common Issues

1. **Images not found**
   ```bash
   # Rebuild images
   ./deploy/build-images.sh
   ```

2. **Services not responding**
   ```bash
   # Check pod status
   kubectl get pods -n image-pipeline
   
   # Check logs
   kubectl logs -n image-pipeline deployment/image-pipeline-api
   ```

3. **Minikube not starting**
   ```bash
   # Delete and recreate
   minikube delete
   minikube start --driver=docker --cpus=4 --memory=8192
   ```

4. **Port conflicts**
   ```bash
   # Check what's using the ports
   lsof -i :30080
   lsof -i :30081
   ```

### Getting Help

- Check pod logs: `kubectl logs -n image-pipeline [pod-name]`
- Check service endpoints: `kubectl get endpoints -n image-pipeline`
- Check events: `kubectl get events -n image-pipeline --sort-by='.lastTimestamp'`

## 🎉 What You've Built

Congratulations! You now have a fully functional image processing pipeline running on Kubernetes with:

- **Event-driven architecture** using RabbitMQ
- **Scalable workers** that can process multiple images
- **Persistent storage** with MinIO for processed images
- **Job tracking** with Redis
- **RESTful APIs** for job creation and status checking
- **Kubernetes-native deployment** with Helm

This setup provides excellent practice for:
- Kubernetes deployments
- Helm chart development
- Microservices architecture
- Event-driven systems
- Container orchestration
- Infrastructure as Code

Happy coding! 🚀
