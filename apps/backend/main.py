"""Sample agent backend for Apigee Labs.

Apigee routes /api/backend/v1/* to this Cloud Run service.
"""

from datetime import datetime, timezone

from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="Apigee Labs Backend Agent")


class HealthResponse(BaseModel):
    status: str
    timestamp: str


class ChatRequest(BaseModel):
    message: str


class ChatResponse(BaseModel):
    reply: str
    agent: str


@app.get("/v1/health", response_model=HealthResponse)
def health():
    return HealthResponse(
        status="ok",
        timestamp=datetime.now(timezone.utc).isoformat(),
    )


@app.post("/v1/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    """Simple echo agent that demonstrates the Apigee → Cloud Run flow."""
    return ChatResponse(
        reply=f"Echo from backend agent: {req.message}",
        agent="sample-echo-agent",
    )
