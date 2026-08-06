# Stage 1: build the wheels. Compilers and build tooling stay in this stage.
FROM python:3.12-slim AS build

WORKDIR /build
COPY requirements.txt ./
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# Stage 2: run. The interpreter, the installed dependencies and the source.
FROM python:3.12-slim

# An unprivileged user, created before anything is copied in, so that nothing in the image is
# owned by root and writable by the process.
RUN useradd --create-home --uid 10001 poller

COPY --from=build /wheels /wheels
COPY requirements.txt ./
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels requirements.txt

WORKDIR /app
COPY src ./src

# PYTHONUNBUFFERED keeps log lines flowing to the container log rather than sitting in a buffer
# until the process exits, which matters most when the process is failing.
ENV PYTHONPATH=/app/src \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER poller
EXPOSE 8083

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import json,urllib.request;\
s=json.load(urllib.request.urlopen('http://localhost:8083/health',timeout=4))['status'];\
raise SystemExit(0 if s in ('ok','starting') else 1)"

# No key is baked in. FAUXNANCE_API_KEY comes from the environment at run time.
ENTRYPOINT ["python", "-m", "market_data_poller"]
