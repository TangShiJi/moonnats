///|
test "every two-chunk boundary produces identical MSG" {
  let wire = b"MSG orders.created 7 reply.inbox 5\r\nhello\r\n"
  for split = 0; split <= wire.length(); split = split + 1 {
    let decoder = @moonnats.protocol_decoder()
    let first = wire[:split].to_owned()
    let second = wire[split:].to_owned()
    let before = decoder.push(first).unwrap()
    let after = decoder.push(second).unwrap()
    assert_eq(before.length() + after.length(), 1)
    let frames = if before.length() == 1 { before } else { after }
    match frames[0] {
      Message(message) => {
        assert_eq(message.subject(), "orders.created")
        assert_eq(message.reply_to(), Some("reply.inbox"))
        assert_eq(message.payload(), b"hello")
      }
      _ => fail("expected message")
    }
  }
}

///|
test "mixed official protocol operations preserve order" {
  let decoder = @moonnats.protocol_decoder()
  let frames = decoder
    .push(
      b"INFO {\"server_id\":\"A\",\"proto\":1}\r\nPING\r\n+OK\r\nMSG foo 1 0\r\n\r\nPONG\r\n",
    )
    .unwrap()
  assert_eq(frames.length(), 5)
  assert_true(frames[0] is Info(_))
  assert_true(frames[1] is Ping)
  assert_true(frames[2] is OkFrame)
  assert_true(frames[3] is Message(_))
  assert_true(frames[4] is Pong)
}

///|
test "malformed frame corpus fails closed" {
  let cases = [
    b"BOGUS\r\n", b"MSG foo x 1\r\na\r\n", b"MSG foo 1 1\r\naXX", b"HMSG foo 1 10 2\r\nxx\r\n",
    b"INFO []\r\n", b"\r\n",
  ]
  for wire in cases {
    assert_true(@moonnats.protocol_decoder().push(wire) is Err(_))
  }
}

///|
test "INFO ignores unknown fields while preserving raw document" {
  let frames = @moonnats.protocol_decoder()
    .push(b"INFO {\"future_capability\":{\"mode\":2},\"headers\":true}\r\n")
    .unwrap()
  match frames[0] {
    Info(info) => {
      assert_true(info.supports_headers())
      assert_true(info.raw_json().contains("future_capability"))
    }
    _ => fail("expected INFO")
  }
}

///|
test "publish and decoder agree on Unicode byte length" {
  let published = @moonnats.encode_publish("text", @utf8.encode("月球"[:])).unwrap()
  let wire_text = @utf8.decode_lossy(published[:])
  assert_true(wire_text.has_prefix("PUB text 6\r\n"))
  let inbound_bytes : Array[Byte] = [
    0x4d, 0x53, 0x47, 0x20, 0x74, 0x65, 0x78, 0x74, 0x20, 0x31, 0x20, 0x36, 0x0d,
    0x0a, 0xe6, 0x9c, 0x88, 0xe7, 0x90, 0x83, 0x0d, 0x0a,
  ]
  let inbound = Bytes::from_array(inbound_bytes[:])
  let frames = @moonnats.protocol_decoder().push(inbound).unwrap()
  match frames[0] {
    Message(message) =>
      assert_eq(@utf8.decode_lossy(message.payload()[:]), "月球")
    _ => fail("expected message")
  }
}

///|
test "ten thousand small control frames decode without buffer growth" {
  let decoder = @moonnats.protocol_decoder(limits=max_buffer_limits())
  for _index = 0; _index < 10000; _index = _index + 1 {
    assert_eq(decoder.push(b"PING\r\n").unwrap(), [Ping])
  }
  assert_eq(decoder.buffered_bytes(), 0)
}

///|
fn max_buffer_limits() -> @moonnats.NatsLimits {
  @moonnats.nats_limits(max_buffer=64)
}
