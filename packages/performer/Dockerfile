## Build stage
FROM golang:1.23.6 AS builder

WORKDIR /app

# Pre-copy go.mod/sum for caching deps
COPY go.mod go.sum ./

ENV GOTOOLCHAIN=auto
RUN go mod download && go mod verify

# Copy the rest and build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/performer ./cmd/performer

## Runtime stage
FROM gcr.io/distroless/base-debian12:nonroot

WORKDIR /app
COPY --from=builder /out/performer /app/performer

ENV PERFORMER_PORT=8080
EXPOSE 8080

USER nonroot:nonroot
ENTRYPOINT ["/app/performer"]


