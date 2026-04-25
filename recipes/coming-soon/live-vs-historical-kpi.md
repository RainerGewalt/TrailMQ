# Live vs Historical KPI *(planned)*

Compare live MQTT values with historical baselines fed via REST. The most
interesting demo in the TrailMQ line-up — it shows the full stack working
together.

## Demo flow
1. Historical baseline is sent via REST (Historical Context Feed plugin)
2. Live MQTT value is published
3. Domain Context Lite extracts machine / batch / metric context
4. KPI Lite compares live vs historical and calculates deviation
5. Decision Trace explains the result
6. Audit Evidence proves what happened

## Status
Planned. Requires four plugins — see
[`plugins/catalog.yaml`](../../plugins/catalog.yaml).
