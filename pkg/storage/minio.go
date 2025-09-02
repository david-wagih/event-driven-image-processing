package storage

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// MinIOClient wraps the MinIO client with additional functionality
type MinIOClient struct {
	Client     *minio.Client
	BucketName string
	Endpoint   string
}

// NewMinIOClient creates a new MinIO client
func NewMinIOClient() (*MinIOClient, error) {
	endpoint := getEnv("MINIO_ENDPOINT", "localhost:9000")
	accessKey := getEnv("MINIO_ACCESS_KEY", "minioadmin")
	secretKey := getEnv("MINIO_SECRET_KEY", "minioadmin123")
	bucketName := getEnv("MINIO_BUCKET", "images")
	useSSL := false // For local development

	// Create MinIO client
	minioClient, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create MinIO client: %w", err)
	}

	client := &MinIOClient{
		Client:     minioClient,
		BucketName: bucketName,
		Endpoint:   endpoint,
	}

	// Ensure bucket exists
	if err := client.ensureBucket(); err != nil {
		return nil, fmt.Errorf("failed to ensure bucket: %w", err)
	}

	return client, nil
}

// ensureBucket creates the bucket if it doesn't exist
func (c *MinIOClient) ensureBucket() error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	exists, err := c.Client.BucketExists(ctx, c.BucketName)
	if err != nil {
		return fmt.Errorf("failed to check bucket existence: %w", err)
	}

	if !exists {
		log.Printf("Creating bucket: %s", c.BucketName)
		err = c.Client.MakeBucket(ctx, c.BucketName, minio.MakeBucketOptions{})
		if err != nil {
			return fmt.Errorf("failed to create bucket: %w", err)
		}
		log.Printf("✅ Bucket %s created successfully", c.BucketName)
	} else {
		log.Printf("✅ Bucket %s already exists", c.BucketName)
	}

	return nil
}

// WaitForMinIO waits for MinIO to be ready with retries
func WaitForMinIO() error {
	maxRetries := 30
	retryDelay := time.Second

	for i := 0; i < maxRetries; i++ {
		_, err := NewMinIOClient()
		if err == nil {
			// MinIO client doesn't have a Close method, just return
			return nil
		}
		log.Printf("⏳ Waiting for MinIO... (attempt %d/%d)", i+1, maxRetries)
		time.Sleep(retryDelay)
	}
	return fmt.Errorf("MinIO not ready after %d attempts", maxRetries)
}

func getEnv(key, fallback string) string {
	if val, ok := os.LookupEnv(key); ok {
		return val
	}
	return fallback
}
