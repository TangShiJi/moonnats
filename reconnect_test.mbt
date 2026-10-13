///|
test "planner rotates eligible seed servers" {
  let planner = @moonnats.reconnect_planner(["a:4222", "b:4222"]).unwrap()
  assert_eq(planner.next(0).unwrap().url(), "a:4222")
  assert_eq(planner.next(0).unwrap().url(), "b:4222")
  assert_eq(planner.next(0).unwrap().url(), "a:4222")
}

///|
test "failure applies capped exponential backoff and caller jitter" {
  let policy = @moonnats.reconnect_policy(
    initial_delay=2,
    maximum_delay=10,
    multiplier=2,
  )
  let planner = @moonnats.reconnect_planner(["a:4222"], policy~).unwrap()
  let first = planner.record_failure("a:4222", 100, jitter=1).unwrap()
  assert_eq(first.next_eligible_tick(), 103)
  assert_true(planner.next(102) is Err({ kind: NoServer, .. }))
  assert_eq(planner.next(103).unwrap().url(), "a:4222")
  let second = planner.record_failure("a:4222", 103, jitter=2).unwrap()
  assert_eq(second.next_eligible_tick(), 109)
}

///|
test "INFO parser exposes discovery and capabilities" {
  let decoder = @moonnats.protocol_decoder()
  let frames = decoder
    .push(
      b"INFO {\"server_id\":\"S1\",\"headers\":true,\"max_payload\":2048,\"connect_urls\":[\"b:4222\",\"c:4222\"]}\r\n",
    )
    .unwrap()
  match frames[0] {
    Info(info) => {
      assert_eq(info.server_id(), Some("S1"))
      assert_true(info.supports_headers())
      assert_eq(info.max_payload(), Some(2048))
      let planner = @moonnats.reconnect_planner(["a:4222"]).unwrap()
      assert_eq(planner.discover(info), Ok(2))
      assert_eq(planner.servers().length(), 3)
    }
    _ => fail("expected INFO")
  }
}

///|
test "reconnect replay preserves remaining auto-unsubscribe allowance" {
  let client = @moonnats.client_core()
  client.begin_connection().unwrap()
  ignore(client.receive(b"INFO {}\r\n").unwrap())
  let sid = client.subscribe("events", max_messages=Some(3)).unwrap()
  ignore(client.drain_outbox())
  ignore(client.receive(b"MSG events 1 1\r\na\r\n").unwrap())
  client.mark_disconnected()
  client.begin_connection().unwrap()
  ignore(client.receive(b"INFO {}\r\n").unwrap())
  assert_eq(client.replay_subscriptions(), Ok(1))
  let frames = client.drain_outbox()
  assert_eq(
    @utf8.decode_lossy(frames[0][:]),
    "SUB events " + sid.to_string() + "\r\n",
  )
  assert_eq(@utf8.decode_lossy(frames[1][:]), "UNSUB 1 2\r\n")
}

///|
test "invalid server addresses and unknown outcomes are rejected" {
  assert_true(@moonnats.reconnect_planner([]) is Err({ kind: NoServer, .. }))
  assert_true(
    @moonnats.reconnect_planner(["no-port"]) is Err({ kind: NoServer, .. }),
  )
  let planner = @moonnats.reconnect_planner(["a:4222"]).unwrap()
  assert_true(
    planner.record_success("missing:4222") is Err({ kind: NoServer, .. }),
  )
}
