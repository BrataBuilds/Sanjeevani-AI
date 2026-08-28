# The triage/RAG service, owned by the AI team. Behind the `ai` compose profile,
# so the default `docker compose up` does not depend on a Gemini key or on
# in-progress work here.
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim
WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PYTHONUNBUFFERED=1

# Dependencies first, so editing source does not reinstall them.
COPY pyproject.toml uv.lock* ./
RUN uv sync --no-install-project --no-dev 2>/dev/null || uv sync --no-dev

COPY . .
RUN uv sync --no-dev

EXPOSE 8000
CMD ["uv", "run", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
