# 🚀 Getting Started Roadmap

### **Step 1: Set Up Your Local Environment**

- Install dependencies:

  - Go (latest stable, e.g. 1.22+)
  - Docker / Podman
  - Minikube (local Kubernetes)
  - kubectl & Helm

- (Optional but nice) Tilt or Skaffold for rapid dev in K8s.

---

### **Step 2: Bootstrap the Repository**

- Create a new GitHub repo (e.g., `image-pipeline`).
- Add basic folders:

  ```
  services/api/
  services/worker/
  services/status/
  pkg/
  deploy/helm/
  ```

- Add a `README.md` describing the architecture & goals.

---

### **Step 3: Write a Minimal API Service**

- Expose a single endpoint: `POST /jobs`
- When called, just enqueue a **dummy job** into RabbitMQ (no image processing yet).
- Push a job ID into Redis with status = `pending`.

_(Goal: confirm API → Queue → Redis integration works.)_

---

### **Step 4: Build the Worker Skeleton**

- Worker consumes jobs from RabbitMQ.
- For now: just log “received job” and mark it `done` in Redis.
- Deploy API + Worker locally with Docker Compose to validate flow.

_(Goal: end-to-end pipeline without image processing.)_

---

### **Step 5: Add Image Processing**

- Pick your library (`imaging` for simplicity).
- Extend worker to:

  - Download the image (HTTP or MinIO/S3).
  - Resize into at least one thumbnail (e.g. 200px).
  - Upload result back to storage.

- Update Redis with result URL.

_(Goal: process one image end-to-end.)_

---

### **Step 6: Containerization**

- Write Dockerfiles for API, Worker, Status.
- Run them locally with Docker Compose (with RabbitMQ, Redis, MinIO).
- Confirm: `curl → POST job → worker processes → Redis updates`.

---

### **Step 7: Kubernetes (Local Deployment)**

- Start Minikube.
- Use Helm to deploy:

  - RabbitMQ, Redis, MinIO (Bitnami charts).
  - Your services (custom Helm chart).

- Verify same workflow inside Kubernetes.

---

### **Step 8: Add Observability**

- Add `/healthz`, `/readyz`, `/metrics` endpoints to all services.
- Deploy Prometheus & Grafana (Helm charts).
- Create simple dashboards (queue depth, job throughput).

---

### **Step 9: AWS Deployment**

- Terraform: provision VPC + EKS + S3.
- Push Docker images to ECR.
- Deploy Helm chart to EKS with S3 backend.
- Use IRSA for worker pods to write to S3.

---

### **Step 10: Polish & Extend**

- Add HPA or KEDA for scaling workers.
- Add dead-letter queue for failed jobs.
- Add notifications/webhooks.
- Optional: basic frontend dashboard.
