# Mooncakes ecosystem audit

Audit date: 2026-10-13. The local Mooncakes registry index was refreshed and
all 2,968 public module metadata records were searched by name, description,
keywords, and repository fields. Search terms included `nats`, `jetstream`,
`message broker`, `message bus`, `subject wildcard`, and `request reply`. A
GitHub search for MoonBit NATS clients was also performed.

No MoonBit NATS or JetStream client was found at this checkpoint.

| Existing module | Actual scope | Boundary from MoonNATS |
|---|---|---|
| `xvyve123/moonflow@0.1.0` | lightweight in-process event bus and message abstraction | no NATS server connection, wire frames, SID, queue groups, or reconnect replay |
| `zbhzs1/moonbit-mqtt@0.1.0` | MQTT 3.1.1 packet codec helpers | different broker protocol and topic/QoS semantics; no NATS operations |
| `liying-han/moonresilience@0.2.0` | generic retry, circuit breaker, rate limit, bulkhead | may complement a transport, but does not understand NATS INFO, messages, subscriptions, or requests |
| `TangShiJi/moonpageflow` | stable cursor pagination | unrelated data-access problem |
| `TangShiJi/moonformflow` | form state and validation | unrelated application-state problem |

The NATS ecosystem page lists maintained clients for several languages but no
MoonBit client. MoonNATS therefore occupies the protocol/client foundation
layer, not the generic event-bus or resilience layers.

This is a dated audit, not a permanent uniqueness claim. The index must be
refreshed again immediately before application submission and before the first
Mooncakes release; any newly published overlap will be documented with a
behavior-level comparison.
