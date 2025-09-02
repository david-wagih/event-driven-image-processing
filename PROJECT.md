# Plan: Image Processing Worker for the Event-Driven Pipeline

## 1. Input & Job Handling

- Consume jobs from RabbitMQ.
- Each job contains:
  - Job ID
  - Image source (upload key or external URL)
  - Desired output formats/sizes

## 2. Image Retrieval

- If uploaded → download from MinIO (local) or S3 (AWS).
- If external URL → fetch via HTTP.
- Validate file type (JPEG, PNG, etc.) and size limits.

## 3. Image Processing

- Decode the image into memory.
- Perform transformations:
  - **Resizing** into multiple thumbnails (e.g. 200px, 800px).
  - **Optional watermarking** with a logo or text overlay.
  - **Format conversion** (JPEG, PNG, WebP).
- Choose a library/tool:
  - **Start simple:** use a pure-Go library (easy in containers).
  - **Later upgrade:** to a high-performance binding like libvips for speed.

## 4. Storage of Results

- Upload processed outputs back to object storage:
  - MinIO in local (Minikube) setup.
  - S3 when deploying to AWS.
- Generate unique keys per job and output format.
- Store metadata (job ID → result URLs).

## 5. Job State Tracking

- Update Redis with:
  - `pending → processing → done` states
  - Error states if processing fails
  - Output file paths for retrieval by the status service

## 6. Observability

- Expose metrics:
  - Number of jobs processed
  - Processing time per job
  - Error rate
- Log job lifecycle events for debugging

## 7. Deployment Considerations

- Containerize the worker service with all required dependencies.
- In Kubernetes:
  - Deploy as a Deployment with multiple replicas.
  - Use an HPA (or KEDA) to scale based on queue length.
- Configure secrets (S3/MinIO credentials, Redis password, RabbitMQ URL).

## 8. Local vs. Cloud Differences

- **Local (Minikube):**
  - Use MinIO for storage.
  - Use Helm to deploy RabbitMQ, Redis, and MinIO.
- **AWS (EKS):**
  - Switch to S3 bucket for storage.
  - Optionally use Amazon MQ (RabbitMQ) and ElastiCache (Redis).
  - Grant workers IAM roles for S3 access (IRSA).

## 9. Stretch Features

- Add support for multiple image operations (crop, rotate, blur).
- Allow custom output formats specified per job.
- Implement retry + dead-letter queue for failed jobs.
- Notify API or clients (via webhook) when job completes.
