# Build Stage
FROM golang:1.24.5 AS build-env

WORKDIR /appsrc

ENV GOPROXY=https://proxy.golang.org,direct

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o main main.go

# Final stage
FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal

ENV APPUSER=appuser
ENV APPUID=1000
ENV APPGID=1000

WORKDIR /app

COPY --chown=1000:1000 --from=build-env /appsrc/main /app/

COPY ./ATTRIBUTION.md ./LICENSES.md

ENV GIN_MODE=release
EXPOSE 8080
USER 1000:1000

ENTRYPOINT ["/app/main"]
