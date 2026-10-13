# Acceptance checklist

## Behavior

- [x] PUB/MSG lengths use bytes, verified with Unicode and binary CRLF payloads.
- [x] MSG/HMSG decode correctly at every two-chunk boundary.
- [x] NATS/1.0 status and repeated headers round-trip without loss.
- [x] Invalid framing, header injection, resource overflow, and unknown SID fail
  with structured errors.
- [x] Request setup is atomic under outbox pressure and timeouts are deterministic.
- [x] INFO discovery, capped backoff, fallback selection, and subscription replay
  preserve remaining delivery allowance.
- [x] Four workflow examples run without external services.
- [ ] Native TCP adapter passes pub/sub, queue, request/reply, and restart-recovery
  tests against a pinned `nats-server` release.
- [ ] Package is published on mooncakes.io after initial project approval.

## Engineering gates

- [x] MoonBit is the primary implementation language.
- [x] Effective production MoonBit source exceeds 1,000 lines.
- [x] At least 10 meaningful commits cover independent implementation units.
- [x] Native and wasm-gc check, build, and tests pass.
- [x] Windows and Ubuntu CI is configured.
- [x] README contains install, API use, examples, verification, and scope.
- [x] Apache-2.0 license and original-implementation notice are present.

Unchecked items are final-delivery work, not claims about the current MVP.
