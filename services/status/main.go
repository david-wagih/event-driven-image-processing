package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"event-driven-image-pipeline/pkg/types"

	"github.com/redis/go-redis/v9"
)

var (
	rdb *redis.Client
	ctx = context.Background()
)

func main() {
	// Connect to Redis
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

	// HTTP routes
	http.HandleFunc("/jobs/", handleGetJob)
	http.HandleFunc("/health", handleHealth)

	addr := getEnv("STATUS_ADDR", ":8001")
	log.Printf("🚀 Status service listening on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}

func handleGetJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "only GET allowed", http.StatusMethodNotAllowed)
		return
	}

	// Extract job ID from URL path
	pathParts := strings.Split(r.URL.Path, "/")
	if len(pathParts) != 3 {
		http.Error(w, "invalid job ID", http.StatusBadRequest)
		return
	}
	jobID := pathParts[2]

	// Get job from Redis
	job, err := getJob(jobID)
	if err != nil {
		if err == redis.Nil {
			http.Error(w, "job not found", http.StatusNotFound)
			return
		}
		http.Error(w, "failed to get job", http.StatusInternalServerError)
		return
	}

	// Return job details
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(job)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "healthy",
		"time":   time.Now().Format(time.RFC3339),
	})
}

// getJob retrieves a job from Redis
func getJob(jobID string) (*types.Job, error) {
	data, err := rdb.Get(ctx, "job:"+jobID).Bytes()
	if err != nil {
		return nil, err
	}

	var job types.Job
	if err := json.Unmarshal(data, &job); err != nil {
		return nil, fmt.Errorf("failed to unmarshal job: %w", err)
	}

	return &job, nil
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

func getEnv(key, fallback string) string {
	if val, ok := os.LookupEnv(key); ok {
		return val
	}
	return fallback
}
