# Architecture

MoonNATS is split into four layers with one-way dependencies:

1. **Protocol primitives** validate subjects, queue groups, lengths, and
   NATS/1.0 headers.
2. **Codec** turns typed client operations into bytes and arbitrary incoming
   chunks into complete server operations.
3. **Client core** owns lifecycle, bounded outbox, subscriptions, keepalive,
   requests, and deterministic timeout bookkeeping.
4. **Recovery policy** owns discovered server candidates, retry eligibility,
   caller-supplied jitter, and subscription replay.

A transport adapter is intentionally thin:

```text
socket.read -> ClientCore.receive -> ClientEvent
application -> ClientCore methods -> drain_outbox -> socket.write_all
timer tick  -> expire_requests / ReconnectPlanner.next
```

The decoder never searches payload bytes for CRLF. It first parses the ASCII
control line, obtains an exact byte length, waits for that many bytes plus the
terminal CRLF, and only then emits a message. HMSG additionally verifies that
the header byte count is no larger than the total byte count.

## Failure rules

- Incomplete data remains buffered within `max_buffer`.
- Invalid framing clears buffered data and returns a structured error.
- Outbox capacity is checked before multi-frame request mutations.
- A disconnect clears only transport state; live subscriptions remain so they
  can be replayed after the next INFO handshake.
- Credentials live in a type without derived Debug output.

## Final-scope transport

The competition delivery will include a native TCP adapter that owns DNS,
connect/read/write scheduling, and reconnection orchestration. TLS remains an
adapter responsibility. Keeping the core free of socket APIs is what permits
the same parser and state tests to run on native and wasm-gc.
