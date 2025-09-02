package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"event-driven-image-pipeline/pkg/processor"
	"event-driven-image-pipeline/pkg/storage"
	"event-driven-image-pipeline/pkg/types"

	amqp "github.com/rabbitmq/amqp091-go"
	"github.com/redis/go-redis/v9"
)

var (
	rdb            *redis.Client
	ctx            = context.Background()
	rmqConn        *amqp.Connection
	rmqChan        *amqp.Channel
	imageProcessor *processor.ImageProcessor
)

func main() {
	// Connect to Redis
	redisURL := getEnv("REDIS_URL", "redis://localhost:6379")
	redisOpts, err := redis.ParseURL(redisURL)
	if err != nil {
		log.Fatalf("failed to parse Redis URL: %v", err)
	}

	rdb = redis.NewClient(redisOpts)
	if err := waitForRedis(); err != nil {
		log.Fatal("Redis connection failed:", err)
	}
	log.Println("✅ Connected to Redis")

	// Connect to RabbitMQ
	rmqURL := getEnv("RABBITMQ_URL", "amqp://guest:guest@localhost:5672/")
	rmqConn, err = waitForRabbitMQ(rmqURL)
	if err != nil {
		log.Fatal("RabbitMQ connection failed:", err)
	}
	defer rmqConn.Close()
	log.Println("✅ Connected to RabbitMQ")

	rmqChan, err = rmqConn.Channel()
	if err != nil {
		log.Fatal("RabbitMQ channel creation failed:", err)
	}
	defer rmqChan.Close()

	// Wait for MinIO
	if err := storage.WaitForMinIO(); err != nil {
		log.Fatal("MinIO connection failed:", err)
	}
	log.Println("✅ Connected to MinIO")

	// Create MinIO client
	minioClient, err := storage.NewMinIOClient()
	if err != nil {
		log.Fatal("Failed to create MinIO client:", err)
	}

	// Create image processor
	imageProcessor = processor.NewImageProcessor(minioClient.Client, minioClient.BucketName)

	// Declare the jobs queue
	_, err = rmqChan.QueueDeclare(
		"jobs",
		true,  // durable
		false, // autoDelete
		false, // exclusive
		false, // noWait
		nil,
	)
	if err != nil {
		log.Fatal("Queue declare failed:", err)
	}

	// Consume messages
	msgs, err := rmqChan.Consume(
		"jobs",
		"",
		true,  // autoAck (can switch to false for manual ack)
		false, // exclusive
		false, // noLocal
		false, // noWait
		nil,
	)
	if err != nil {
		log.Fatal("Failed to register consumer:", err)
	}

	log.Println("🚀 Worker started. Waiting for jobs...")

	for msg := range msgs {
		var job types.Job
		if err := json.Unmarshal(msg.Body, &job); err != nil {
			log.Println("❌ Failed to parse job:", err)
			continue
		}

		log.Printf("📥 Received job: %s (status: %s)", job.ID, job.Status)

		// Update job to "in_progress"
		job.Status = types.StatusInProgress
		saveJob(job)

		// Process the image
		if err := imageProcessor.ProcessJob(ctx, &job); err != nil {
			log.Printf("❌ Failed to process job %s: %v", job.ID, err)
			job.Status = types.StatusFailed
			job.Error = err.Error()
			saveJob(job)
			continue
		}

		// Save final job state
		saveJob(job)
		log.Printf("✅ Finished job: %s with %d results", job.ID, len(job.Results))
	}
}

// waitForRedis waits for Redis to be ready with retries
func waitForRedis() error {
	maxRetries := 30
	retryDelay := time.Second

	for i := 0; i < maxRetries; i++ {
		if err := rdb.Ping(ctx).Err(); err == nil {
			return nil
		}
		log.Printf("⏳ Waiting for Redis... (attempt %d/%d)", i+1, maxRetries)
		time.Sleep(retryDelay)
	}
	return fmt.Errorf("Redis not ready after %d attempts", maxRetries)
}

// waitForRabbitMQ waits for RabbitMQ to be ready with retries
func waitForRabbitMQ(url string) (*amqp.Connection, error) {
	maxRetries := 30
	retryDelay := time.Second

	for i := 0; i < maxRetries; i++ {
		if conn, err := amqp.Dial(url); err == nil {
			return conn, nil
		}
		log.Printf("⏳ Waiting for RabbitMQ... (attempt %d/%d)", i+1, maxRetries)
		time.Sleep(retryDelay)
	}
	return nil, fmt.Errorf("RabbitMQ not ready after %d attempts", maxRetries)
}

// saveJob updates Redis with the job status
func saveJob(job types.Job) {
	data, _ := json.Marshal(job)
	if err := rdb.Set(ctx, fmt.Sprintf("job:%s", job.ID), data, 24*time.Hour).Err(); err != nil {
		log.Println("❌ Failed to save job to Redis:", err)
	}
}

func getEnv(key, fallback string) string {
	if val, ok := os.LookupEnv(key); ok {
		return val
	}
	return fallback
}
