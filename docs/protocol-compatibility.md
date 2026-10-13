# NATS protocol compatibility

Reference: [NATS Client Protocol](https://docs.nats.io/reference/protocols/client).

| Operation | Direction | MVP status | Verification |
|---|---|---:|---|
| INFO | server → client | complete core fields + unknown-field preservation | JSON/capability/discovery tests |
| CONNECT | client → server | complete Core NATS options used by this project | deterministic encoder tests |
| PUB | client → server | subject, optional reply, binary payload | Unicode and binary fixtures |
| HPUB | client → server | NATS/1.0 multi-value headers | exact header/total length tests |
| SUB | client → server | plain and queue subscriptions | registry and wire fixtures |
| UNSUB | client → server | immediate and max-message | replay remaining-count test |
| MSG | server → client | incremental binary-safe decode | every split boundary + fuzz chunks |
| HMSG | server → client | status and regular headers | body/header separation tests |
| PING/PONG | both | keepalive and flush barrier | lifecycle tests |
| +OK/-ERR | server → client | typed events | mixed-operation fixture |

## Deliberate exclusions for 0.1

- JetStream consumer, stream, ack, and persistence APIs;
- NKey/JWT challenge signing;
- an embedded NATS server;
- TLS implementation (transport supplies encrypted bytes);
- WebSocket framing and proxy configuration.

These exclusions do not change Core NATS wire parsing. They keep the first
release testable against a local `nats-server` without claiming JetStream or
authentication behavior that has not been implemented.
