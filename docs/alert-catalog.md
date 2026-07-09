# CloudLink — Alert Catalog

Every alert configured for this integration: what triggers it, how it's routed, and where the resolution steps live. This is the artifact an on-call person should be able to open at 2am and immediately know what to do.

| Alert | Metric | Threshold | Frequency / Window | Severity | Routes to | Runbook |
|---|---|---|---|---|---|---|
| `cloudlink-dlq-depth-alert` | `Messages` count on `orders-dlq` (Service Bus namespace metric, dimension `EntityName = orders-dlq`) | Average > 5 | Evaluated every 5 min over a 15 min window | 2 (Warning) | Action group `cloudlink-oncall` → email | [`runbook-dlq-alert.md`](runbook-dlq-alert.md) |

## Alert design notes

- **Why average over 15 minutes, not a point-in-time count.** A single burst of 5 failures during a brief downstream blip is expected noise; a sustained average above threshold indicates the downstream dependency is actually down or degraded, not a transient hiccup.
- **Why severity 2, not 1.** Messages are durable in the DLQ (7-day TTL) and not lost — this is "needs attention this shift," not "wake someone up at 3am." If DLQ TTL is ever shortened, this severity should be revisited since message loss risk changes the calculus.
- **Threshold is a variable, not hardcoded** (`dlq_alert_threshold` in `infra/main.tf`), so it can be tuned per environment without touching the alert logic itself.

## Alerts intentionally not yet implemented (see dependency-catalog.md "Known gaps")

- Logic App run-failure alert (covers failures upstream of the DLQ-routing step, e.g. Service Bus itself unavailable).
- APIM throttling/429 rate alert (pending the APIM policy implementation).
- Downstream API latency/error-rate alert (would require shipping downstream logs to Log Analytics — not yet wired up).

These are called out explicitly rather than silently absent, so anyone reviewing this project (or taking over the on-call rotation) knows the coverage boundary.
