///|
test "publish encoder counts bytes rather than Unicode characters" {
  let frame = @moonnats.encode_publish("events.created", @utf8.encode("月"[:])).unwrap()
  assert_eq(@utf8.decode_lossy(frame[:]), "PUB events.created 3\r\n月\r\n")
}

///|
test "publish encoder preserves binary CRLF in payload" {
  let payload = Bytes::from_array([0x00, 0x0d, 0x0a, 0xff])
  let frame = @moonnats.encode_publish("binary", payload).unwrap()
  assert_eq(frame.length(), b"PUB binary 4\r\n".length() + 4 + 2)
  assert_eq(frame[b"PUB binary 4\r\n".length()], 0x00)
}

///|
test "header publish uses header and total byte lengths" {
  let headers = @moonnats.nats_headers().append("Trace", "abc").unwrap()
  let frame = @moonnats.encode_header_publish("events", headers, b"ok").unwrap()
  assert_true(@utf8.decode_lossy(frame[:]).has_prefix("HPUB events 24 26\r\n"))
}

///|
test "subscribe and unsubscribe validate identifiers" {
  assert_eq(
    @utf8.decode_lossy(
      @moonnats.encode_subscribe("jobs.*", 3, queue=Some("workers")).unwrap()[:],
    ),
    "SUB jobs.* workers 3\r\n",
  )
  assert_eq(
    @utf8.decode_lossy(
      @moonnats.encode_unsubscribe(3, max_messages=Some(10)).unwrap()[:],
    ),
    "UNSUB 3 10\r\n",
  )
  assert_true(@moonnats.encode_subscribe("jobs", 0) is Err(_))
}

///|
test "connect frame escapes user text and never adds missing credentials" {
  let frame = @moonnats.encode_connect(
    @moonnats.connect_options(name=Some("worker \"a\"")),
  )
  let text = @utf8.decode_lossy(frame[:])
  assert_true(text.has_prefix("CONNECT {"))
  assert_true(text.contains("\"name\":\"worker \\\"a\\\"\""))
  assert_false(text.contains("auth_token"))
}
