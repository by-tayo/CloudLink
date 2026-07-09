# Runbook: `cloudlink-dlq-depth-alert`

**Alert fires when:** average message count on `orders-dlq` exceeds 5 over a 15-minute window.

**What it means:** the Logic App has been unable to reach the downstream fulfillment API, even after 4 retries with exponential backoff, for multiple orders in a row. Orders are safe (durable in the DLQ, 7-day TTL) but are not being fulfilled.

## 1. Confirm the alert and scope the impact

```bash
# Current DLQ depth
az servicebus queue show \
  --resource-group cloudlink-rg \
  --namespace-name <namespace-from-terraform-output> \
  --name orders-dlq \
  --query "countDetails.activeMessageCount"
```

Note the count and how fast it's climbing — that tells you if this is a brief blip that's already resolving or an ongoing outage.

## 2. Check the downstream fulfillment API

```bash
curl -s https://cloudlink-downstream.example.com/health
```

- If this fails or times out → the downstream system is down. This is likely not a CloudLink problem; escalate to the downstream fulfillment team and reference the correlation IDs from step 3.
- If this succeeds → the downstream system is up now but wasn't during the failure window (recovered blip), or the issue is elsewhere (auth, network path from Logic App, payload shape). Continue to step 3.

## 3. Pull correlation IDs from failed messages

Peek at DLQ messages without removing them (use Service Bus Explorer in the Azure Portal, or the CLI below), and note the `correlation_id` and `failure_reason` properties on each.

```bash
az servicebus queue message peek \
  --resource-group cloudlink-rg \
  --namespace-name <namespace> \
  --queue-name orders-dlq \
  --max-count 10
```

Cross-reference a correlation ID against the Logic App run history (Azure Portal → Logic App → Runs History → filter by time window) to see the exact failure at each retry attempt.

## 4. Decide: replay or investigate further

- **If the downstream API is confirmed healthy again:** replay the DLQ messages back into the `orders` queue (or re-POST them through `/orders` — same idempotency guarantee via `order_id` applies either way, so replays are safe even if some already partially succeeded).
- **If the downstream API is still degraded:** do not replay yet — you'll just refill the DLQ. Escalate and wait for confirmation, then replay in step 5.

## 5. Replay

```bash
# Example: re-submit a single order captured from a peeked DLQ message
curl -X POST https://cloudlink-apim.azure-api.net/orders \
  -H "Content-Type: application/json" \
  -H "Ocp-Apim-Subscription-Key: <key>" \
  -d '{"order_id": "ord_123", "sku": "WIDGET-1", "qty": 2}'
```

For bulk replay, script the above over all peeked DLQ messages. Complete removal of a message from the DLQ (vs. peek) should only happen after you've confirmed the replay succeeded — don't destructively pop-and-hope.

## 6. Close out

- Confirm DLQ depth is back under threshold and stable.
- If root cause was a downstream outage: note the duration and impact for the postmortem/tracking ticket.
- If root cause was something CloudLink-side (e.g., a bad transform, an auth misconfiguration): file a follow-up to fix the underlying issue, not just replay past it.
