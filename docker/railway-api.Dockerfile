# The API and the agent loop, in one container — Railway variant.
#
# Identical to docker/api.Dockerfile except for two omissions that Railway's
# builder rejects or duplicates:
#
#   VOLUME /data   — Railway mounts its own persistent volume at /data; the
#                    declaration in the image conflicts with that.
#   HEALTHCHECK    — Railway runs its own healthcheck against /health, set on
#                    the service (healthcheckPath), so the image-level one is
#                    redundant on this platform.
#
# Everything else is a byte-for-byte copy, so `git diff` against the upstream
# file stays readable and upstream changes are easy to carry over.
#
# Build context is the repository root:
#   docker build -f docker/railway-api.Dockerfile .

FROM python:3.12-slim AS build

WORKDIR /app

# Dependencies first, on their own layer, so editing a source file does not
# reinstall the world. Setuptools refuses to even report requirements without the
# package directories, so two empty ones stand in for them on this layer.
COPY pyproject.toml README.md ./
RUN mkdir -p api agent && pip install --no-cache-dir .

COPY api/ api/
COPY agent/ agent/
COPY locales/ locales/
COPY alembic/ alembic/
COPY alembic.ini ./
COPY scripts/ scripts/
# The package itself again, now that its source is present.
RUN pip install --no-cache-dir --no-deps --force-reinstall .

# ---------------------------------------------------------------------------

FROM python:3.12-slim

# Never root: this process parses strangers' input for a living (§B14).
RUN useradd --create-home --uid 1000 telagent
WORKDIR /app

COPY --from=build /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=build /usr/local/bin /usr/local/bin
COPY --from=build /app /app
COPY docker/api-entrypoint.sh /entrypoint.sh

# Conversations, the SQLite database and backups live here. On Railway this path
# is a mounted volume; the directory is still created so a run without one works.
RUN mkdir -p /data && chown telagent:telagent /data /app

USER telagent

ENV BIND_HOST=0.0.0.0 \
    BIND_PORT=38472 \
    DATABASE_URL=sqlite+aiosqlite:////data/tel-agent.db

EXPOSE 38472

# Via `sh` rather than directly: a COPY from a Windows checkout has no execute
# bit to preserve, and the script does not need one this way.
ENTRYPOINT ["sh", "/entrypoint.sh"]
