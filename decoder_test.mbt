///|
test "decoder waits across every frame boundary" {
  let decoder = @moonnats.protocol_decoder()
  assert_eq(decoder.push(b"MS").unwrap(), [])
  assert_eq(decoder.buffered_bytes(), 2)
  assert_eq(decoder.push(b"G events 7 5\r\nhe").unwrap(), [])
  let frames = decoder.push(b"llo\r\nPING\r\n").unwrap()
  assert_eq(frames.length(), 2)
  match frames[0] {
    Message(message) => {
      assert_eq(message.subject(), "events")
      assert_eq(message.sid(), 7)
      assert_eq(message.payload(), b"hello")
    }
    _ => fail("expected message")
  }
  assert_true(frames[1] is Ping)
  assert_eq(decoder.buffered_bytes(), 0)
}

///|
test "decoder handles binary payload containing CRLF" {
  let decoder = @moonnats.protocol_decoder()
  let wire = Bytes::from_array([
    0x4d, 0x53, 0x47, 0x20, 0x62, 0x69, 0x6e, 0x20, 0x31, 0x20, 0x34, 0x0d, 0x0a,
    0x00, 0x0d, 0x0a, 0xff, 0x0d, 0x0a,
  ])
  let frames = decoder.push(wire).unwrap()
  match frames[0] {
    Message(message) =>
      assert_eq(message.payload(), Bytes::from_array([0x00, 0x0d, 0x0a, 0xff]))
    _ => fail("expected message")
  }
}

///|
test "decoder splits HMSG header section from body" {
  let headers = @moonnats.encode_headers(
    @moonnats.nats_headers(
      status_code=Some(503),
      status_text=Some("No Responders"),
    ),
  ).unwrap()
  let prefix = "HMSG _INBOX.1 2 " +
    headers.length().to_string() +
    " " +
    (headers.length() + 3).to_string() +
    "\r\n"
  let bytes : Array[Byte] = []
  for byte in @utf8.encode(prefix[:]) {
    bytes.push(byte)
  }
  for byte in headers {
    bytes.push(byte)
  }
  for byte in b"nil\r\n" {
    bytes.push(byte)
  }
  let frame = Bytes::from_array(bytes[:])
  let frames = @moonnats.protocol_decoder().push(frame).unwrap()
  match frames[0] {
    Message(message) => {
      assert_eq(message.payload(), b"nil")
      assert_eq(message.headers().unwrap().status_code(), Some(503))
    }
    _ => fail("expected header message")
  }
}

///|
test "decoder recognizes control operations" {
  let frames = @moonnats.protocol_decoder()
    .push(
      b"INFO {\"server_id\":\"s1\"}\r\n+OK\r\nPONG\r\n-ERR 'Permissions Violation'\r\n",
    )
    .unwrap()
  assert_true(frames[0] is Info(_))
  assert_true(frames[1] is OkFrame)
  assert_true(frames[2] is Pong)
  assert_eq(frames[3], ServerError("Permissions Violation"))
}

///|
test "decoder enforces resource limits and resets after failure" {
  let limits = @moonnats.nats_limits(
    max_control_line=20,
    max_buffer=64,
    max_payload=3,
  )
  let decoder = @moonnats.protocol_decoder(limits~)
  assert_true(
    decoder.push(b"MSG events 1 4\r\ntest\r\n")
    is Err({ kind: PayloadTooLarge, .. }),
  )
  assert_eq(decoder.buffered_bytes(), 0)
  assert_eq(decoder.push(b"PING\r\n").unwrap(), [Ping])
  assert_true(
    decoder.push(b"ABCDEFGHIJKLMNOPQRSTU") is Err({ kind: FrameTooLarge, .. }),
  )
}

///|
test "decoder rejects mismatched payload terminator" {
  let decoder = @moonnats.protocol_decoder()
  assert_true(
    decoder.push(b"MSG events 1 2\r\nokXX")
    is Err({ kind: ProtocolViolation, .. }),
  )
}
