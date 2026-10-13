# MoonNATS

MoonNATS is a binary-safe NATS protocol codec and recoverable Sans-I/O client
state machine written in MoonBit. It owns protocol framing, subscriptions,
request/reply, keepalive, backpressure, server discovery, reconnect policy, and
subscription replay while leaving socket scheduling to a small transport
adapter.

That split is deliberate: the same tested core can sit behind native TCP, a
WebSocket bridge, an embedded event loop, or a deterministic simulator. It is
not an in-process event bus and it does not implement a broker.

## Status

The current MVP contains:

- subject and queue-group validation with NATS `*` and `>` semantics;
- binary-safe CONNECT/PUB/HPUB/SUB/UNSUB/PING/PONG encoding;
- incremental INFO/MSG/HMSG/PING/PONG/+OK/-ERR decoding across arbitrary chunks;
- lossless NATS/1.0 headers, including repeated fields and status lines;
- bounded decoder buffers, payloads, subscriptions, outbox, and pending pings;
- subscription dispatch, max-delivery accounting, and reconnect replay;
- atomic request/reply inbox setup and deterministic timeouts;
- INFO server discovery and caller-controlled exponential backoff;
- native and wasm-gc tests plus four runnable workflow examples.

The final competition scope also includes a native TCP adapter and black-box
tests against `nats-server`. TLS is delegated to the selected transport; the
library does not implement cryptography. JetStream persistence, NKey/JWT auth,
WebSocket transport, and a broker are explicit non-goals for this release.

## Install

From the public source repository:

```bash
git clone https://github.com/TangShiJi/moonnats.git
cd moonnats
moon test
```

After the first Mooncakes release:

```bash
moon add TangShiJi/moonnats
```

Then import it from `moon.pkg`:

```text
import {
  "TangShiJi/moonnats",
}
```

## Minimal use

MoonNATS does not hide transport I/O. Feed received chunks to `receive`, then
write every frame returned by `drain_outbox` in order:

```mbt
let client = @moonnats.client_core()
client.begin_connection().unwrap()

// Bytes read from a socket may end at any boundary.
ignore(client.receive(b"INFO {\"headers\":true}\r\n").unwrap())
client.send_connect(@moonnats.connect_options(name=Some("orders"))).unwrap()
let sid = client.subscribe("orders.*").unwrap()
client.publish("orders.created", b"order-42").unwrap()

for frame in client.drain_outbox() {
  // transport.write_all(frame)
  ignore(frame)
}
ignore(sid)
```

For request/reply, the core queues the subscription, one-message unsubscribe,
and publish as one mutation:

```mbt
let request = client.request("math.add", b"40,2", 100, 30).unwrap()
println(request.inbox())
let expired = client.expire_requests(130).unwrap()
ignore(expired)
```

## Reproducible examples

```bash
moon run examples/event_bus
moon run examples/queue_workers
moon run examples/request_reply
moon run examples/reconnect
moon run cmd/main
```

## Verification

```bash
moon fmt --check
moon check --target native --deny-warn
moon build --target native --deny-warn
moon test --target native --deny-warn
moon check --target wasm-gc --deny-warn
moon build --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
moon info
pwsh ./tools/source-metrics.ps1
pwsh ./tools/benchmark.ps1
```

CI runs formatting, check, build, all tests, examples, package inspection, and
the source-size guard on both Windows and Ubuntu. See
[`docs/acceptance.md`](docs/acceptance.md) for behavior-level criteria.

## Design notes

- Lengths are byte counts, never Unicode character counts.
- A partial control line or payload stays buffered; complete operations are
  emitted exactly once.
- Any framing error clears the decoder buffer so callers cannot accidentally
  continue from ambiguous bytes.
- Request deadlines use caller-owned monotonic ticks rather than wall-clock
  time, keeping native and wasm behavior reproducible.
- Reconnect jitter is supplied by the caller, making randomized production
  policy deterministic under test.
- Credentials are not included in Debug-derived values.

Further details: [`docs/architecture.md`](docs/architecture.md),
[`docs/protocol-compatibility.md`](docs/protocol-compatibility.md), and
[`docs/ecosystem-audit.md`](docs/ecosystem-audit.md).

## License

Apache License 2.0. This is an original implementation based on the public NATS
protocol specification; no NATS client source code was copied or ported.
