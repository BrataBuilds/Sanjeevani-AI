#!/usr/bin/env bash
# One command to bring the whole stack up.
#
#   bash run.sh              db + API + staff console + patient app (web)
#   bash run.sh --profile ai   ...and the AI team's triage service
#
# Any extra arguments are passed straight through to `docker compose up`.
#
# Exists because JWT_SECRET has no default -- the backend refuses to start
# without one, deliberately -- so a first run needs a secret generated before
# compose is invoked. Everything else this does is `docker compose up --build`.
set -euo pipefail
cd "$(dirname "$0")"

rand() {
  # openssl on most systems, node as the fallback since the repo needs it anyway.
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$1"
  else
    node -e "console.log(require('crypto').randomBytes($1).toString('hex'))"
  fi
}

# Fill in a value only when the key is present but empty. Never overwrites a
# secret you already set, so this is safe to run repeatedly.
fill_if_empty() {
  local key="$1" value="$2"
  if grep -qE "^${key}=$" .env; then
    # A generated hex secret contains no / or &, so plain sed is fine here.
    sed -i.bak "s|^${key}=$|${key}=${value}|" .env && rm -f .env.bak
    echo "  generated ${key}"
  fi
}

if [ ! -f .env ]; then
  echo "no .env -- creating one from .env.example"
  cp .env.example .env
fi

fill_if_empty JWT_SECRET "$(rand 32)"
fill_if_empty AI_CALLBACK_SECRET "$(rand 24)"

# `--profile` is a top-level compose flag, not an `up` flag, so it cannot just be
# forwarded. Pull it out of the arguments and use COMPOSE_PROFILES instead.
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) export COMPOSE_PROFILES="${COMPOSE_PROFILES:+$COMPOSE_PROFILES,}$2"; shift 2 ;;
    --profile=*) export COMPOSE_PROFILES="${COMPOSE_PROFILES:+$COMPOSE_PROFILES,}${1#*=}"; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

# Turn the seam on only when the AI service is actually starting. Pointing the
# backend at a service that is not running would replace stub answers -- which
# demo fine -- with "the assistant is unavailable".
case ",${COMPOSE_PROFILES:-}," in
  *,ai,*)
    if ! grep -qE "^GEMINI_API=.+" .env; then
      echo "GEMINI_API is empty in .env -- the ai profile needs a Gemini key." >&2
      exit 1
    fi
    export AI_SERVICE_URL="${AI_SERVICE_URL:-http://rag:8000}"
    echo "  AI seam on: backend -> $AI_SERVICE_URL"
    ;;
esac

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running. Start Docker Desktop and try again." >&2
  exit 1
fi

echo
echo "building and starting -- first run pulls the Flutter SDK image, so give it a while"
echo
docker compose up --build ${ARGS[@]+"${ARGS[@]}"}
