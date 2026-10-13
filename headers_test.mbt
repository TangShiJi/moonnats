///|
test "headers round trip repeated fields and status" {
  let headers = @moonnats.nats_headers(
      status_code=Some(503),
      status_text=Some("No Responders"),
    )
    .append("Trace-Id", "a")
    .unwrap()
    .append("Trace-Id", "b")
    .unwrap()
  let encoded = @moonnats.encode_headers(headers).unwrap()
  let decoded = @moonnats.decode_headers(encoded).unwrap()
  assert_eq(decoded.status_code(), Some(503))
  assert_eq(decoded.status_text(), Some("No Responders"))
  assert_eq(decoded.values("trace-id"), ["a", "b"])
}

///|
test "headers reject injection and malformed preambles" {
  assert_true(@moonnats.nats_headers().append("Bad\r\nInjected", "x") is Err(_))
  assert_true(@moonnats.nats_headers().append("Safe", "x\r\ny") is Err(_))
  assert_true(@moonnats.decode_headers(b"HTTP/1.1 200\r\n\r\n") is Err(_))
}

///|
test "header size is checked before parsing" {
  let limits = @moonnats.nats_limits(max_headers=8)
  let result = @moonnats.decode_headers(b"NATS/1.0\r\n\r\n", limits~)
  assert_true(result is Err({ kind: FrameTooLarge, .. }))
}
