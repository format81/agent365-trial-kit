"""FastAPI web host for the LangChain agent, ready for Azure App Service.

Endpoints:
  GET  /            -> service metadata
  GET  /health      -> health probe used by App Service
  POST /api/chat    -> simple chat endpoint {"message": "..."} -> {"reply": "..."}
  POST /api/messages-> messaging endpoint placeholder for Agent 365 integration

Run locally:
    uvicorn src.app:app --reload --port 8000

On Azure App Service (Linux, Python), set the startup command to:
    python -m uvicorn src.app:app --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

import logging

from fastapi import FastAPI
from pydantic import BaseModel

from .agent import run_once
from .config import PORT, agent as agent_cfg
from .observability import try_enable_observability

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("agent365.app")

app = FastAPI(title=agent_cfg.name, version="0.1.0")


@app.on_event("startup")
async def _startup() -> None:
    enabled = try_enable_observability()
    logger.info("Agent '%s' started. Observability enabled=%s", agent_cfg.name, enabled)


class ChatRequest(BaseModel):
    message: str


class ChatResponse(BaseModel):
    reply: str


@app.get("/")
async def root() -> dict:
    return {"agent": agent_cfg.name, "status": "running"}


@app.get("/health")
async def health() -> dict:
    return {"status": "healthy"}


@app.post("/api/chat", response_model=ChatResponse)
async def chat(req: ChatRequest) -> ChatResponse:
    reply = run_once(req.message)
    return ChatResponse(reply=reply)


@app.post("/api/messages")
async def messages(payload: dict) -> dict:
    """Messaging endpoint placeholder.

    Register this URL with Agent 365 after deployment:
        a365 setup blueprint --endpoint-only \
            --messaging-endpoint https://<your-app>.azurewebsites.net/api/messages

    Replace this stub with the Agent 365 SDK activity handler when integrating
    Teams/Outlook notifications:
    https://learn.microsoft.com/microsoft-agent-365/developer/notification
    """
    text = payload.get("text") or payload.get("message") or ""
    reply = run_once(text) if text else "No message text provided."
    return {"type": "message", "text": reply}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)
