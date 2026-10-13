# Contributing

Run `moon fmt`, native and wasm-gc checks, and all tests before opening a pull
request. A protocol change must include an exact wire fixture, a chunk-boundary
case, and documentation of any compatibility impact. Keep transport-specific
I/O outside the protocol core.
