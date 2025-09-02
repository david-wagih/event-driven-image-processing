# ---- Build stage ----
FROM golang:1.24.3 AS builder

WORKDIR /app

# Copy go mod files from root project
COPY go.mod go.sum ./
RUN go mod download

# Copy the entire project (so dependencies resolve)
COPY . .

# Build the status binary
WORKDIR /app/services/status
RUN go build -o /status main.go

# ---- Runtime stage ----
FROM gcr.io/distroless/base-debian12

WORKDIR /app
COPY --from=builder /status /app/status

EXPOSE 8001
CMD ["/app/status"]
