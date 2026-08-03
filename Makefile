.PHONY: up down logs test

# Build images, start both services, and wait until their healthchecks pass.
up:
	docker compose up -d --build --wait

# Remove containers and the project network; named volumes would be removed too.
down:
	docker compose down --volumes --remove-orphans

# Follow recent logs from both services.
logs:
	docker compose logs --follow --tail=200

# Validate JSON, request-ID handling, and the per-client rate limit (POSIX shell).
test:
	sh scripts/test.sh
