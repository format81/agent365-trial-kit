# Container image for the LangChain agent (FastAPI host).
# Build context is the DEV/ folder. Sidesteps the Oryx zip-deploy pitfalls
# (Windows backslash paths, venv extraction) by baking dependencies into layers.
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

WORKDIR /app

# Install dependencies first for better layer caching.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Application code.
COPY src ./src

EXPOSE 8000

# App Service for Containers / ACA both route to the port the app listens on.
CMD ["python", "-m", "uvicorn", "src.app:app", "--host", "0.0.0.0", "--port", "8000"]
