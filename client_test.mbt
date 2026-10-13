///|
fn connected_client() -> @moonnats.ClientCore {
  let client = @moonnats.client_core()
  client.begin_connection().unwrap()
  ignore(client.receive(b"INFO {\"server_id\":\"s1\"}\r\n").unwrap())
  client
}

///|
test "client enforces handshake state" {
  let client = @moonnats.client_core()
  assert_true(client.publish("events", b"x") is Err({ kind: InvalidState, .. }))
  client.begin_connection().unwrap()
  assert_eq(client.state(), AwaitingInfo)
  let events = client.receive(b"INFO {\"server_id\":\"s1\"}\r\n").unwrap()
  assert_true(events[0] is ServerInformation(_))
  assert_eq(client.state(), Connected)
}

///|
test "client queues connect publish and drains atomically" {
  let client = connected_client()
  client.send_connect(@moonnats.connect_options(name=Some("worker"))).unwrap()
  client.publish("events.created", b"one").unwrap()
  assert_eq(client.outbox_length(), 2)
  let frames = client.drain_outbox()
  assert_eq(frames.length(), 2)
  assert_true(@utf8.decode_lossy(frames[0][:]).has_prefix("CONNECT "))
  assert_eq(@utf8.decode_lossy(frames[1][:]), "PUB events.created 3\r\none\r\n")
  assert_eq(client.outbox_length(), 0)
}

///|
test "client registers and dispatches subscription messages" {
  let client = connected_client()
  let sid = client.subscribe("events.*", max_messages=Some(1)).unwrap()
  assert_eq(sid, 1)
  assert_eq(client.drain_outbox().length(), 2)
  let events = client.receive(b"MSG events.created 1 2\r\nok\r\n").unwrap()
  match events[0] {
    Delivered(result) => {
      assert_eq(result.message().payload(), b"ok")
      assert_true(result.auto_unsubscribed())
    }
    _ => fail("expected delivery")
  }
  assert_eq(client.subscriptions(), [])
}

///|
test "client answers server PING and resolves flush PONG" {
  let client = connected_client()
  client.flush().unwrap()
  assert_eq(client.pending_pings(), 1)
  let events = client.receive(b"PING\r\nPONG\r\n").unwrap()
  assert_eq(events, [KeepAliveReplied, FlushCompleted])
  assert_eq(client.pending_pings(), 0)
  assert_eq(client.drain_outbox(), [b"PING\r\n", b"PONG\r\n"])
}

///|
test "outbox backpressure rolls subscription registration back" {
  let limits = @moonnats.nats_limits(max_outbox=1)
  let client = @moonnats.client_core(limits~)
  client.begin_connection().unwrap()
  ignore(client.receive(b"INFO {}\r\n").unwrap())
  client.publish("events", b"x").unwrap()
  assert_true(client.subscribe("jobs") is Err({ kind: OutboxFull, .. }))
  assert_eq(client.subscriptions(), [])
}

///|
test "disconnect preserves subscriptions for replay but clears transport state" {
  let client = connected_client()
  ignore(client.subscribe("events"))
  client.flush().unwrap()
  client.mark_disconnected()
  assert_eq(client.state(), Disconnected)
  assert_eq(client.outbox_length(), 0)
  assert_eq(client.pending_pings(), 0)
  assert_eq(client.subscriptions().length(), 1)
}
