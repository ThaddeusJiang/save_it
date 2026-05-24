#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f ".env" ]]; then
  echo "Missing .env at $ROOT_DIR/.env"
  exit 1
fi

echo "[1/3] Build image save_it:ac"
docker build -t save_it:ac -f Dockerfile .

echo "[2/3] Start dependencies with docker compose"
docker compose up -d cobalt-api typesense typelens

echo "[3/3] Run save_it:ac with .env"
docker run --rm --name save_it-preview \
  --env-file .env \
  -e COBALT_API_URL="http://cobalt-api:9000" \
  -e TYPESENSE_URL="http://typesense:8108" \
  --network save_it_default \
  save_it:ac
