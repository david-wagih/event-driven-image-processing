package processor

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"log"
	"net/http"
	"strings"
	"time"

	"event-driven-image-pipeline/pkg/types"

	"github.com/disintegration/imaging"
	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
)

// ImageProcessor handles image processing operations
type ImageProcessor struct {
	minioClient *minio.Client
	bucketName  string
}

// NewImageProcessor creates a new image processor instance
func NewImageProcessor(minioClient *minio.Client, bucketName string) *ImageProcessor {
	return &ImageProcessor{
		minioClient: minioClient,
		bucketName:  bucketName,
	}
}

// ProcessJob processes a complete image processing job
func (p *ImageProcessor) ProcessJob(ctx context.Context, job *types.Job) error {
	startTime := time.Now()

	// Download the source image
	img, err := p.downloadImage(ctx, job.ImageURL)
	if err != nil {
		return fmt.Errorf("failed to download image: %w", err)
	}

	// Process each operation
	var results []types.ProcessedImage
	for _, op := range job.Operations {
		result, err := p.processOperation(ctx, img, op, job.ID)
		if err != nil {
			log.Printf("Failed to process operation %s: %v", op.Type, err)
			continue
		}
		results = append(results, result)
	}

	// Update job with results
	job.Results = results
	job.Status = types.StatusCompleted
	now := time.Now()
	job.CompletedAt = &now

	log.Printf("✅ Processed job %s in %v with %d results",
		job.ID, time.Since(startTime), len(results))

	return nil
}

// downloadImage downloads an image from URL or object storage
func (p *ImageProcessor) downloadImage(ctx context.Context, imageURL string) (image.Image, error) {
	if strings.HasPrefix(imageURL, "http://") || strings.HasPrefix(imageURL, "https://") {
		return p.downloadFromHTTP(ctx, imageURL)
	}

	// Assume it's an object storage key
	return p.downloadFromStorage(ctx, imageURL)
}

// downloadFromHTTP downloads an image from HTTP URL
func (p *ImageProcessor) downloadFromHTTP(ctx context.Context, url string) (image.Image, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to download image: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP error: %d", resp.StatusCode)
	}

	img, err := imaging.Decode(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to decode image: %w", err)
	}

	return img, nil
}

// downloadFromStorage downloads an image from object storage
func (p *ImageProcessor) downloadFromStorage(ctx context.Context, objectKey string) (image.Image, error) {
	obj, err := p.minioClient.GetObject(ctx, p.bucketName, objectKey, minio.GetObjectOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get object from storage: %w", err)
	}
	defer obj.Close()

	img, err := imaging.Decode(obj)
	if err != nil {
		return nil, fmt.Errorf("failed to decode image: %w", err)
	}

	return img, nil
}

// processOperation processes a single image operation
func (p *ImageProcessor) processOperation(ctx context.Context, img image.Image, op types.ImageOperation, jobID string) (types.ProcessedImage, error) {
	startTime := time.Now()

	// Apply the operation
	processedImg, err := p.applyOperation(img, op)
	if err != nil {
		return types.ProcessedImage{}, fmt.Errorf("failed to apply operation: %w", err)
	}

	// Generate output key
	if op.OutputKey == "" {
		op.OutputKey = fmt.Sprintf("processed/%s/%s_%s", jobID, op.Type, uuid.New().String()[:8])
	}

	// Upload result
	outputURL, err := p.uploadResult(ctx, processedImg, op)
	if err != nil {
		return types.ProcessedImage{}, fmt.Errorf("failed to upload result: %w", err)
	}

	// Get image dimensions
	bounds := processedImg.Bounds()

	result := types.ProcessedImage{
		Operation:      op,
		OutputURL:      outputURL,
		OutputKey:      op.OutputKey,
		Width:          bounds.Dx(),
		Height:         bounds.Dy(),
		Format:         op.Format,
		ProcessingTime: time.Since(startTime),
	}

	return result, nil
}

// applyOperation applies a single operation to an image
func (p *ImageProcessor) applyOperation(img image.Image, op types.ImageOperation) (image.Image, error) {
	var result image.Image = img

	// Apply resize if specified
	if op.Type == types.OpResize && (op.Width > 0 || op.Height > 0) {
		if op.Width > 0 && op.Height > 0 {
			result = imaging.Resize(result, op.Width, op.Height, imaging.Lanczos)
		} else if op.Width > 0 {
			result = imaging.Resize(result, op.Width, 0, imaging.Lanczos)
		} else {
			result = imaging.Resize(result, 0, op.Height, imaging.Lanczos)
		}
	}

	// Apply watermark if specified
	if op.Type == types.OpWatermark && op.Watermark != "" {
		// Simple text watermark for now
		result = p.addWatermark(result, op.Watermark)
	}

	return result, nil
}

// addWatermark adds a simple text watermark to the image
func (p *ImageProcessor) addWatermark(img image.Image, text string) image.Image {
	// For now, we'll just return the original image
	// TODO: Implement actual watermarking
	log.Printf("Watermarking not yet implemented, returning original image")
	return img
}

// uploadResult uploads the processed image to object storage
func (p *ImageProcessor) uploadResult(ctx context.Context, img image.Image, op types.ImageOperation) (string, error) {
	// Encode image to bytes
	var buf bytes.Buffer
	var err error

	switch op.Format {
	case types.FormatJPEG:
		quality := op.Quality
		if quality == 0 {
			quality = 90
		}
		err = jpeg.Encode(&buf, img, &jpeg.Options{Quality: quality})
	case types.FormatPNG:
		err = png.Encode(&buf, img)
	case types.FormatWebP:
		// WebP encoding not yet implemented, fallback to JPEG
		log.Printf("WebP not yet implemented, falling back to JPEG")
		err = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 90})
	default:
		// Default to JPEG
		err = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 90})
	}

	if err != nil {
		return "", fmt.Errorf("failed to encode image: %w", err)
	}

	// Add file extension
	ext := "." + op.Format
	if ext == ".jpeg" {
		ext = ".jpg"
	}
	objectKey := op.OutputKey + ext

	// Upload to MinIO
	_, err = p.minioClient.PutObject(ctx, p.bucketName, objectKey, &buf, int64(buf.Len()), minio.PutObjectOptions{
		ContentType: "image/" + op.Format,
	})
	if err != nil {
		return "", fmt.Errorf("failed to upload to storage: %w", err)
	}

	// Return the object key (in production, this would be a full URL)
	return objectKey, nil
}
