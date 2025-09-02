package types

import (
	"time"
)

// Job represents an image processing job
type Job struct {
	ID          string           `json:"id"`
	Status      string           `json:"status"`
	ImageURL    string           `json:"image_url"`
	Operations  []ImageOperation `json:"operations"`
	CreatedAt   time.Time        `json:"created_at"`
	CompletedAt *time.Time       `json:"completed_at,omitempty"`
	Results     []ProcessedImage `json:"results,omitempty"`
	Error       string           `json:"error,omitempty"`
}

// ImageOperation defines what should be done to the image
type ImageOperation struct {
	Type      string `json:"type"`       // resize, format, watermark
	Width     int    `json:"width"`      // for resize operations
	Height    int    `json:"height"`     // for resize operations
	Format    string `json:"format"`     // jpeg, png, webp
	Quality   int    `json:"quality"`    // 1-100 for JPEG/WebP
	Watermark string `json:"watermark"`  // watermark text or logo path
	OutputKey string `json:"output_key"` // unique key for this output
}

// ProcessedImage represents the result of image processing
type ProcessedImage struct {
	Operation      ImageOperation `json:"operation"`
	OutputURL      string         `json:"output_url"`
	OutputKey      string         `json:"output_key"`
	Size           int64          `json:"size"` // file size in bytes
	Width          int            `json:"width"`
	Height         int            `json:"height"`
	Format         string         `json:"format"`
	ProcessingTime time.Duration  `json:"processing_time"`
}

// JobStatus constants
const (
	StatusPending    = "pending"
	StatusInProgress = "in_progress"
	StatusCompleted  = "completed"
	StatusFailed     = "failed"
)

// OperationType constants
const (
	OpResize    = "resize"
	OpFormat    = "format"
	OpWatermark = "watermark"
)

// ImageFormat constants
const (
	FormatJPEG = "jpeg"
	FormatPNG  = "png"
	FormatWebP = "webp"
)
