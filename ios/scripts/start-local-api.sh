#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
API_DIR="$REPO_ROOT/api"
LOG_DIR="$SCRIPT_DIR/.logs"
OVERRIDE_ENV="$API_DIR/override.env"
SEED_MARKER="$LOG_DIR/.api-data-seeded"

mkdir -p "$LOG_DIR"

for command_name in brew curl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command_name" >&2
    exit 1
  fi
done

missing_formulae=()
for formula in uv postgresql@17 opensearch node@24; do
  if ! brew list --versions "$formula" >/dev/null 2>&1; then
    missing_formulae+=("$formula")
  fi
done
if ((${#missing_formulae[@]})); then
  brew install "${missing_formulae[@]}"
fi

export PATH="$(brew --prefix postgresql@17)/bin:$(brew --prefix uv)/bin:$(brew --prefix node@24)/bin:$PATH"
if ! command -v node >/dev/null 2>&1; then
  printf 'Node.js 24 was not found after Homebrew installation\n' >&2
  exit 1
fi

uv python install 3.14

if ! pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
  brew services start postgresql@17
  touch "$LOG_DIR/.started-postgresql"
fi

for attempt in {1..60}; do
  if pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" == 60 ]]; then
    printf 'PostgreSQL did not become ready; inspect %s\n' "$LOG_DIR" >&2
    exit 1
  fi
  sleep 1
done

postgres_version="$(psql -d postgres -tAc 'SHOW server_version_num' | tr -d '[:space:]')"
if [[ "$postgres_version" != 17* ]]; then
  printf 'PostgreSQL 17 is required; found server_version_num=%s on port 5432\n' \
    "$postgres_version" >&2
  exit 1
fi

psql -d postgres -v ON_ERROR_STOP=1 -c \
  "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app') THEN CREATE ROLE app LOGIN PASSWORD 'secret123'; ELSE ALTER ROLE app WITH LOGIN PASSWORD 'secret123'; END IF; END \$\$;"
if ! psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'app'" | rg -q '^1$'; then
  createdb -O app app
fi

opensearch_config="$(brew --prefix)/etc/opensearch/opensearch.yml"
if [[ ! -f "$opensearch_config" ]]; then
  printf 'OpenSearch config not found: %s\n' "$opensearch_config" >&2
  exit 1
fi
/usr/bin/python3 - "$opensearch_config" <<'PY'
from pathlib import Path
import re
import sys

config = Path(sys.argv[1])
managed = {
    "discovery.type": "single-node",
    "cluster.routing.allocation.disk.threshold_enabled": "false",
}
obsolete = {"plugins.security.disabled"}
lines = config.read_text().splitlines()
lines = [
    line
    for line in lines
    if not any(
        re.match(rf"^\s*{re.escape(key)}\s*:", line) for key in managed.keys() | obsolete
    )
]
lines.extend(f"{key}: {value}" for key, value in managed.items())
config.write_text("\n".join(lines) + "\n")
PY

if ! curl -fsS http://127.0.0.1:9200/_cluster/health >/dev/null 2>&1; then
  if lsof -nP -iTCP:9200 -sTCP:LISTEN >/dev/null 2>&1; then
    if brew services list | rg -q '^opensearch[[:space:]]+started'; then
      brew services restart opensearch
    else
      printf 'Port 9200 is already in use by a non-Homebrew OpenSearch service\n' >&2
      exit 1
    fi
  else
    if brew services list | rg -q '^opensearch[[:space:]]+error'; then
      brew services stop opensearch || true
    fi
    brew services start opensearch
    touch "$LOG_DIR/.started-opensearch"
  fi
fi

for attempt in {1..120}; do
  if curl -fsS http://127.0.0.1:9200/_cluster/health >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" == 120 ]]; then
    printf 'OpenSearch did not become ready; inspect Homebrew OpenSearch logs\n' >&2
    exit 1
  fi
  sleep 1
done

if [[ ! -f "$OVERRIDE_ENV" ]]; then
  (cd "$API_DIR" && ./bin/setup-env-override-file.sh)
fi

/usr/bin/python3 - "$OVERRIDE_ENV" "$API_DIR" <<'PY'
from pathlib import Path
import sys

override = Path(sys.argv[1])
api_dir = Path(sys.argv[2])
settings = {
    "DB_HOST": "127.0.0.1",
    "SEARCH_ENDPOINT": "127.0.0.1",
    "SEARCH_PORT": "9200",
    "SEARCH_USE_SSL": "FALSE",
    "SEARCH_VERIFY_CERTS": "FALSE",
    "AWS_S3_ENDPOINT_URL": "http://127.0.0.1:4566",
    "AWS_SQS_ENDPOINT_URL": "http://127.0.0.1:4566",
    "AWS_DYNAMODB_ENDPOINT_URL": "http://127.0.0.1:4566",
    "WORKFLOW_QUEUE_URL": "http://127.0.0.1:4566/123456789012/local_workflow_queue",
    "LOGIN_GOV_ENDPOINT": "http://127.0.0.1:5001/issuer1",
    "LOGIN_GOV_JWK_ENDPOINT": "http://127.0.0.1:5001/issuer1/jwks",
    "LOGIN_GOV_AUTH_ENDPOINT": "http://127.0.0.1:5001/issuer1/authorize",
    "LOGIN_GOV_TOKEN_ENDPOINT": "http://127.0.0.1:5001/issuer1/token",
    "LOGIN_GOV_LOGOUT_ENDPOINT": "http://127.0.0.1:5001/issuer1/endsession",
    "LOGIN_FINAL_DESTINATION": "http://127.0.0.1:8080/v1/users/login/result",
    "LOCAL_S3_STORE_PATH": str(api_dir / "locals3root"),
    "ENABLE_LOCAL_FILE_SCANNER": "FALSE",
    "ENABLE_LOCAL_EMAIL_CAPTURE": "FALSE",
    "LOCAL_EMAIL_SMTP_HOST": "localhost",
}
lines = override.read_text().splitlines()
managed_keys = set(settings)
lines = [line for line in lines if line.partition("=")[0] not in managed_keys]
lines.extend(f"{key}={value}" for key, value in settings.items())
override.write_text("\n".join(lines) + "\n")
PY

cd "$API_DIR"
uv sync --all-groups --locked
eval "$(
  uv run python - "$API_DIR/local.env" "$OVERRIDE_ENV" <<'PY'
from dotenv import dotenv_values
from pathlib import Path
import os
import shlex
import sys

settings = {}
for env_file in sys.argv[1:]:
    settings.update(
        {key: value for key, value in dotenv_values(Path(env_file)).items() if value is not None}
    )
for key, value in settings.items():
    if key not in os.environ:
        print(f"export {key}={shlex.quote(value)}")
PY
)"
export PY_RUN_APPROACH=local
export AWS_ACCESS_KEY_ID=local
export AWS_SECRET_ACCESS_KEY=local
export AWS_DEFAULT_REGION=us-east-1

start_background() {
  local name="$1"
  local port="$2"
  local logfile="$3"
  local pidfile="$LOG_DIR/$name.pid"
  shift 3

  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    return
  fi
  rm -f "$pidfile"
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    printf 'Port %s is already in use; refusing to replace an unknown process\n' "$port" >&2
    exit 1
  fi
  nohup "$@" >>"$logfile" 2>&1 </dev/null &
  echo "$!" >"$pidfile"
}

start_background moto 4566 "$LOG_DIR/moto.log" uv run moto_server -H 127.0.0.1 -p 4566
for attempt in {1..60}; do
  if curl -fsS http://127.0.0.1:4566/ >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" == 60 ]]; then
    printf 'Moto did not become ready; inspect %s/moto.log\n' "$LOG_DIR" >&2
    exit 1
  fi
  sleep 1
done

queue_url="$(uv run python - <<'PY'
import boto3
from botocore.exceptions import ClientError

endpoint = "http://127.0.0.1:4566"
s3 = boto3.client("s3", endpoint_url=endpoint, region_name="us-east-1")
for bucket in (
    "local-mock-public-bucket",
    "local-mock-draft-bucket",
    "local-mock-file-scan-bucket",
):
    try:
        s3.head_bucket(Bucket=bucket)
    except ClientError:
        s3.create_bucket(Bucket=bucket)
sqs = boto3.client("sqs", endpoint_url=endpoint, region_name="us-east-1")
print(sqs.create_queue(QueueName="local_workflow_queue")["QueueUrl"])
PY
)"
export WORKFLOW_QUEUE_URL="$queue_url"
/usr/bin/python3 - "$OVERRIDE_ENV" "$queue_url" <<'PY'
from pathlib import Path
import sys

override = Path(sys.argv[1])
lines = [
    line for line in override.read_text().splitlines()
    if not line.startswith("WORKFLOW_QUEUE_URL=")
]
lines.append(f"WORKFLOW_QUEUE_URL={sys.argv[2]}")
override.write_text("\n".join(lines) + "\n")
PY

make PY_RUN_APPROACH=local setup-postgres-db
make PY_RUN_APPROACH=local db-migrate
uv run setup-local-dynamodb

start_background mock-oauth 5001 "$LOG_DIR/mock-oauth.log" \
  env MOCK_OAUTH_PORT=5001 MOCK_OAUTH_ISSUER=http://127.0.0.1:5001/issuer1 \
  node "$REPO_ROOT/api/mock-oauth/server.js"

if [[ ! -f "$SEED_MARKER" ]]; then
  make PY_RUN_APPROACH=local setup-api-data
  touch "$SEED_MARKER"
else
  make PY_RUN_APPROACH=local populate-search-opportunities populate-search-agencies
fi

start_background api 8080 "$LOG_DIR/api.log" \
  uv run flask --app src.app run --host 0.0.0.0 --port 8080

for attempt in {1..120}; do
  if curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
    printf 'API health: '
    curl -fsS http://127.0.0.1:8080/health
    printf '\nAPI: http://localhost:8080\nOpenSearch: http://localhost:9200\n'
    printf 'Mock login.gov: http://localhost:5001\nMoto (S3/SQS/DynamoDB): http://localhost:4566\n'
    printf 'Logs: %s\n' "$LOG_DIR"
    exit 0
  fi
  if [[ "$attempt" == 120 ]]; then
    printf 'API did not become ready; inspect %s/api.log\n' "$LOG_DIR" >&2
    exit 1
  fi
  sleep 1
done
