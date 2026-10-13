# Maintenance plan

## Compatibility policy

- 0.x releases may add protocol capabilities, but existing public functions and
  structured error categories are not removed without a deprecation cycle.
- Every supported NATS operation has a wire fixture and at least one chunked
  decode test. Protocol changes add fixtures before implementation.
- The CI toolchain is pinned. Toolchain upgrades are separate commits and must
  pass native/wasm-gc plus examples on Windows and Ubuntu.

## Release checklist

1. Refresh the complete Mooncakes index and update `ecosystem-audit.md`.
2. Run formatting, both target checks/builds/tests, examples, source metrics,
   and the codec smoke benchmark.
3. Run pinned `nats-server` black-box tests once the TCP adapter lands.
4. Inspect `moon package --list` for accidental fixtures or credentials.
5. Update changelog and protocol compatibility table.
6. Tag the same commit published to mooncakes.io.

## Security and limits

Resource limits remain default-on. Reports involving length parsing, memory
growth, credential exposure, or state desynchronization receive priority. Test
fixtures must never contain live NATS credentials.
