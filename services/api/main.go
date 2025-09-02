package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"event-driven-image-pipeline/pkg/types"

	"github.com/google/uuid"
	"github.com/rabbitmq/amqp091-go"
	"github.com/redis/go-redis/v9"
)

var (
	rdb     *redis.Client
	rmqChan *amqp091.Channel
	ctx     = context.Background()
)

func main() {
	// --- Redis ---
	redisURL := getEnv("REDIS_URL", "redis://localhost:6379")
	redisOpts, err := redis.ParseURL(redisURL)
	if err != nil {
		log.Fatalf("failed to parse Redis URL: %v", err)
	}

	rdb = redis.NewClient(redisOpts)

	// Test Redis connection with retry
	if err := waitForRedis(); err != nil {
		log.Fatalf("failed to connect to Redis: %v", err)
	}
	log.Println("✅ Connected to Redis")

	// --- RabbitMQ ---
	rmqURL := getEnv("RABBITMQ_URL", "amqp://guest:guest@localhost:5672/")
	conn, err := waitForRabbitMQ(rmqURL)
	if err != nil {
		log.Fatalf("failed to connect to RabbitMQ: %v", err)
	}
	defer conn.Close()
	log.Println("✅ Connected to RabbitMQ")

	rmqChan, err = conn.Channel()
	if err != nil {
		log.Fatalf("failed to open channel: %v", err)
	}
	defer rmqChan.Close()

	// Declare queue
	_, err = rmqChan.QueueDeclare(
		"jobs", true, false, false, false, nil,
	)
	if err != nil {
		log.Fatalf("failed to declare queue: %v", err)
	}

	// --- HTTP Server ---
	http.HandleFunc("/jobs", handleCreateJob)
	http.HandleFunc("/health", handleHealth)

	addr := getEnv("API_ADDR", ":8000")
	log.Printf("🚀 API listening on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}

func handleCreateJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "only POST allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse request body
	var req struct {
		ImageURL   string                 `json:"image_url"`
		Operations []types.ImageOperation `json:"operations"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	// Validate request
	if req.ImageURL == "" {
		http.Error(w, "image_url is required", http.StatusBadRequest)
		return
	}

	if len(req.Operations) == 0 {
		// Default operation: resize to 800x600
		req.Operations = []types.ImageOperation{
			{
				Type:      types.OpResize,
				Width:     800,
				Height:    600,
				Format:    types.FormatJPEG,
				Quality:   90,
				OutputKey: "",
			},
		}
	}

	// Generate job ID and create job
	jobID := uuid.New().String()
	now := time.Now()
	job := types.Job{
		ID:         jobID,
		Status:     types.StatusPending,
		ImageURL:   req.ImageURL,
		Operations: req.Operations,
		CreatedAt:  now,
	}

	// Store initial status in Redis
	if err := saveJob(job); err != nil {
		http.Error(w, "failed to save job", http.StatusInternalServerError)
		return
	}

	// Publish job to RabbitMQ
	body, _ := json.Marshal(job)
	err := rmqChan.PublishWithContext(ctx,
		"",     // default exchange
		"jobs", // queue name
		false,  // mandatory
		false,  // immediate
		amqp091.Publishing{
			ContentType: "application/json",
			Body:        body,
		},
	)
	if err != nil {
		http.Error(w, "failed to publish job", http.StatusInternalServerError)
		return
	}

	// Respond with job details
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message": "Job created successfully",
		"job":     job,
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "healthy",
		"time":   time.Now().Format(time.RFC3339),
	})
}

// saveJob saves job to Redis
func saveJob(job types.Job) error {
	data, _ := json.Marshal(job)
	return rdb.Set(ctx, "job:"+job.ID, data, 24*time.Hour).Err()
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
func waitForRabbitMQ(url string) (*amqp091.Connection, error) {
	maxRetries := 30
	retryDelay := time.Second

	for i := 0; i < maxRetries; i++ {
		if conn, err := amqp091.Dial(url); err == nil {
			return conn, nil
		}
		log.Printf("⏳ Waiting for RabbitMQ... (attempt %d/%d)", i+1, maxRetries)
		time.Sleep(retryDelay)
	}
	return nil, fmt.Errorf("RabbitMQ not ready after %d attempts", maxRetries)
}

func getEnv(key, fallback string) string {
	if val, ok := os.LookupEnv(key); ok {
		return val
	}
	return fallback
}
