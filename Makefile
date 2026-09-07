# ==============================================================================
# Caddy Reverse Proxy Build System
# ==============================================================================

CADDY_VERSION ?= $(shell sed -n 's/^ARG CADDY_VERSION="//p' Dockerfile | cut -d'"' -f1 | head -n 1 | tr -d '\n\r ')
VERSION_TAG   ?= $(shell [ -s version.txt ] && printf 'v%s\n' $$(cat version.txt | tr -d '[:space:]' | sed 's/^v*//') || echo 'latest')

REGISTRY        := ghcr.io/andygodish
IMAGE_NAME      := caddy
FULL_TAG        := $(REGISTRY)/$(IMAGE_NAME):$(VERSION_TAG)
LATEST_TAG      := $(REGISTRY)/$(IMAGE_NAME):latest
REPO_ROOT       := $(shell pwd)

PLATFORMS       ?= linux/amd64,linux/arm64

COMPOSE_FILE    := $(shell test -f docker-compose.yaml && echo docker-compose.yaml || echo docker-compose.yml)
CONTAINER_NAME  := caddy
HTTP_PORT       ?= 80
HTTPS_PORT      ?= 443
PUID            ?= 10005
PGID            ?= 10005
RENOVATE_IMAGE  ?= renovate/renovate:latest

.DEFAULT_GOAL := help

.PHONY: verify-env build build-multiarch up run stop down restart logs status ps verify-ports fix-permissions test renovate-validate renovate-dry-run help

verify-env:
	@if [ ! -f version.txt ]; then \
		echo "Error: version.txt file missing in repository root."; \
		exit 1; \
	fi

build: verify-env
	@echo "Building local architecture image $(IMAGE_NAME):$(VERSION_TAG)..."
	docker build \
		--build-arg CADDY_VERSION=$(CADDY_VERSION) \
		-t $(IMAGE_NAME):$(VERSION_TAG) \
		-t $(FULL_TAG) \
		$(REPO_ROOT)
	@echo "Local slice build complete."

build-multiarch: verify-env
	@echo "Initializing Buildx engine multi-arch compilation & push..."
	@echo "Target Registry: $(REGISTRY)"
	@echo "Platforms targeted: $(PLATFORMS)"
	docker buildx build \
		--platform $(PLATFORMS) \
		--build-arg CADDY_VERSION=$(CADDY_VERSION) \
		-t $(FULL_TAG) \
		-t $(LATEST_TAG) \
		--push \
		$(REPO_ROOT)
	@echo "Multi-arch build successfully pushed to GHCR!"

up: build verify-ports fix-permissions
	@echo "Running standalone Caddy reverse proxy stack..."
	docker compose -f $(COMPOSE_FILE) up -d --force-recreate --remove-orphans
	@echo "Caddy is running on http://127.0.0.1:$(HTTP_PORT) and https://127.0.0.1:$(HTTPS_PORT). Run 'make status' to verify health."

run: up

stop down:
	@echo "Safely bringing down Caddy reverse proxy stack..."
	docker compose -f $(COMPOSE_FILE) down

restart:
	@echo "Gracefully restarting Caddy reverse proxy stack..."
	docker compose -f $(COMPOSE_FILE) restart

logs:
	docker compose -f $(COMPOSE_FILE) logs -f --tail=100

status ps:
	docker compose -f $(COMPOSE_FILE) ps

verify-ports:
	@echo "Running preflight network checks..."
	@if docker inspect -f "{{.State.Running}}" $(CONTAINER_NAME) 2>/dev/null | grep -qx true; then \
		echo "Existing $(CONTAINER_NAME) container is running; Compose may recreate it for upgrades."; \
	elif lsof -Pi :$(HTTP_PORT) -sTCP:LISTEN -t >/dev/null 2>&1; then \
		echo "ERROR: Port $(HTTP_PORT) is already occupied by another process."; \
		echo "Stop that process or run with a different HTTP_PORT before starting Caddy."; \
		exit 1; \
	elif lsof -Pi :$(HTTPS_PORT) -sTCP:LISTEN -t >/dev/null 2>&1; then \
		echo "ERROR: Port $(HTTPS_PORT) is already occupied by another process."; \
		echo "Stop that process or run with a different HTTPS_PORT before starting Caddy."; \
		exit 1; \
	else \
		echo "Target network ports $(HTTP_PORT) and $(HTTPS_PORT) are clear."; \
	fi

fix-permissions:
	@echo "Caddy uses Docker named volumes; no host path permissions to normalize."

test: verify-env
	@echo "Validating Caddy runtime..."
	docker run --rm \
		--entrypoint caddy \
		$(IMAGE_NAME):$(VERSION_TAG) \
		version
	@echo "Validating Caddyfile..."
	docker run --rm \
		--entrypoint caddy \
		$(IMAGE_NAME):$(VERSION_TAG) \
		validate --config /etc/caddy/Caddyfile --adapter caddyfile
	@echo "Internal validation passed."

renovate-validate:
	docker run --rm \
		-v $(REPO_ROOT):/usr/src/app \
		-w /usr/src/app \
		$(RENOVATE_IMAGE) \
		renovate-config-validator

renovate-dry-run:
	docker run --rm \
		-v $(REPO_ROOT):/usr/src/app \
		-w /usr/src/app \
		-e LOG_LEVEL=debug \
		$(RENOVATE_IMAGE) \
		renovate --platform=local --dry-run=lookup --onboarding=false --require-config=optional

help:
	@echo "Caddy Reverse Proxy Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make build            Build local architecture Caddy image"
	@echo "  make build-multiarch  Build and push multi-platform images via Buildx"
	@echo "  make up               Build and run the standalone Caddy compose stack"
	@echo "  make down             Safely stop and remove containers (keeps volumes intact)"
	@echo "  make restart          Gracefully restart the Caddy service"
	@echo "  make logs             Stream live Caddy logs"
	@echo "  make status           View operational health and port bindings"
	@echo "  make test             Query Caddy and validate the bundled Caddyfile"
	@echo "  make renovate-validate Validate renovate.json with Renovate"
	@echo "  make renovate-dry-run  Run Renovate local lookup dry-run"
