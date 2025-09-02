# ---- Build stage ----
FROM golang:1.24.3 AS builder

WORKDIR /app

# Copy go mod files from root project
COPY go.mod go.sum ./
RUN go mod download

# Copy the whole project
COPY . .

# Build the worker binary
WORKDIR /app/services/worker
RUN go build -o /worker main.go

# ---- Runtime stage ----
FROM gcr.io/distroless/base-debian12

WORKDIR /app
COPY --from=builder /worker /app/worker

CMD ["/app/worker"]
