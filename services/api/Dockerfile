# ---- Build stage ----
FROM golang:1.24.3 AS builder

WORKDIR /app

# Copy go mod files from root project
COPY go.mod go.sum ./
RUN go mod download

# Copy the entire project (so dependencies resolve)
COPY . .

# Build the API binary
WORKDIR /app/services/api
RUN go build -o /api main.go

# ---- Runtime stage ----
FROM gcr.io/distroless/base-debian12

WORKDIR /app
COPY --from=builder /api /app/api

EXPOSE 8080
CMD ["/app/api"]
