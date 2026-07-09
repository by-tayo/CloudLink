"""
CloudLink downstream fulfillment API (mock).

Stands in for the "real" backend system the Logic App calls after transforming
an inbound order. Supports configurable failure injection so you can exercise
the Logic App's retry policy and Service Bus DLQ routing without needing a
flaky real dependency.

Run:
    uvicorn main:app --reload --port 8080

Env vars:
    SIMULATE_FAILURE_RATE   float 0.0-1.0, probability a request 500s (default 0.0)
    SIMULATE_LATENCY_MS     int, artificial latency per request (default 0)
"""
import logging
import os
import random
import time
import uuid
from typing import Optional

from fastapi import FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, Field

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s correlation_id=%(correlation_id)s %(message)s",
)
logger = logging.getLogger("cloudlink.downstream")

app = FastAPI(title="CloudLink Downstream Fulfillment API", version="1.0.0")

FAILURE_RATE = float(os.getenv("SIMULATE_FAILURE_RATE", "0.0"))
LATENCY_MS = int(os.getenv("SIMULATE_LATENCY_MS", "0"))

# In-memory idempotency store (demo only — use Redis/DB in a real deployment)
_seen_order_ids: set[str] = set()


class OrderPayload(BaseModel):
    order_id: str = Field(..., description="Unique order identifier from upstream")
    sku: str
    qty: int = Field(..., gt=0)


class FulfillmentResponse(BaseModel):
    status: str
    order_id: str
    correlation_id: str
    duplicate: bool = False


def _log_extra(correlation_id: str) -> dict:
    return {"correlation_id": correlation_id}


@app.middleware("http")
async def add_correlation_id(request: Request, call_next):
    correlation_id = request.headers.get("x-correlation-id", str(uuid.uuid4()))
    request.state.correlation_id = correlation_id
    response = await call_next(request)
    response.headers["x-correlation-id"] = correlation_id
    return response


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/fulfillment", response_model=FulfillmentResponse)
async def fulfill_order(
    payload: OrderPayload,
    request: Request,
    x_correlation_id: Optional[str] = Header(default=None),
):
    correlation_id = getattr(request.state, "correlation_id", str(uuid.uuid4()))

    if LATENCY_MS:
        time.sleep(LATENCY_MS / 1000)

    # Idempotency check — Logic App or MQ consumer retries should not double-fulfill
    if payload.order_id in _seen_order_ids:
        logger.info(
            "duplicate order_id=%s — returning idempotent response",
            payload.order_id,
            extra=_log_extra(correlation_id),
        )
        return FulfillmentResponse(
            status="already_fulfilled",
            order_id=payload.order_id,
            correlation_id=correlation_id,
            duplicate=True,
        )

    # Failure injection — lets you test the Logic App retry policy + DLQ path
    if random.random() < FAILURE_RATE:
        logger.warning(
            "simulated failure for order_id=%s",
            payload.order_id,
            extra=_log_extra(correlation_id),
        )
        raise HTTPException(status_code=503, detail="simulated downstream failure")

    _seen_order_ids.add(payload.order_id)
    logger.info(
        "fulfilled order_id=%s sku=%s qty=%d",
        payload.order_id,
        payload.sku,
        payload.qty,
        extra=_log_extra(correlation_id),
    )
    return FulfillmentResponse(
        status="fulfilled", order_id=payload.order_id, correlation_id=correlation_id
    )
