# CloudLink — Dependency & Endpoint Catalog

Inventory of every system, endpoint, and message artifact in this integration, and how they depend on each other. Kept current by hand for this project; in a real environment this would be paired with an auto-generated version (e.g. from Terraform state + APIM exports).

## Endpoints

| Endpoint | Method | Owner | Consumed by | Auth |
|---|---|---|---|---|
| `https://cloudlink-apim.azure-api.net/orders` | POST | API Management | External clients | Subscription key |
| Logic App trigger URL (SAS-signed, generated at deploy) | POST | Logic App runtime | API Management only | SAS signature in URL |
| `https://cloudlink-downstream.example.com/fulfillment` | POST | Downstream fulfillment team (mocked in this project) | Logic App | Bearer token (not yet implemented — TODO) |
| `/health` on downstream API | GET | Downstream fulfillment team | Uptime monitoring | None |

## Message artifacts

| Artifact | Type | Purpose | TTL | Alerting |
|---|---|---|---|---|
| `orders` queue | Service Bus queue | Reserved for future queue-triggered intake (see architecture doc) | 1 day | Not currently alerted |
| `orders-dlq` queue | Service Bus queue | Receives messages after Logic App retries (4 attempts) exhausted | 7 days | Yes — see `alert-catalog.md` |

## System dependencies

```
API Management
   └── depends on: Logic App (order-intake)
Logic App (order-intake)
   ├── depends on: Downstream Fulfillment API (hard dependency — request path)
   ├── depends on: Service Bus / orders-dlq (soft dependency — only on failure path)
   └── depends on: Azure Monitor (for downstream alerting, not a runtime dependency)
Azure Monitor
   └── depends on: Service Bus namespace metrics (Messages count on orders-dlq)
   └── notifies: Action Group → on-call email
```

## Failure blast radius

If the **downstream fulfillment API** is unavailable:
- Logic App retries 4x with exponential backoff (5s → up to 1m intervals), then routes to `orders-dlq`.
- Caller receives `502 routed_to_dlq` — not a silent failure.
- DLQ depth alert fires once threshold (default: 5 messages / 15 min window) is exceeded.

If **Service Bus** is unavailable:
- The DLQ-routing step itself fails; the Logic App run shows as Failed in run history (no silent data loss, but no automatic alert on *this specific* failure mode yet — noted as a gap below).

## Known gaps

- No alert on Logic App run failures that occur *before* reaching the DLQ-routing step (e.g., Service Bus itself being down). Recommend adding a Logic-App-level "run failure" alert as a follow-up.
- Downstream API auth (Bearer token) is not yet implemented — currently unauthenticated for local development.
