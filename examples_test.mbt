///|
test "event bus scenario decodes a complete delivery" {
  let client = @moonnats.client_core()
  client.begin_connection().unwrap()
  ignore(client.receive(b"INFO {}\r\n").unwrap())
  ignore(client.subscribe("orders.*"))
  ignore(client.drain_outbox())
  let events = client.receive(b"MSG orders.paid 1 2\r\nok\r\n").unwrap()
  assert_true(events[0] is Delivered(_))
}

///|
test "worker scenario preserves queue group on the wire" {
  let frame = @moonnats.encode_subscribe(
    "jobs.resize",
    7,
    queue=Some("image-workers"),
  ).unwrap()
  assert_eq(@utf8.decode_lossy(frame[:]), "SUB jobs.resize image-workers 7\r\n")
}

///|
test "request scenario expires when no responder arrives" {
  let client = @moonnats.client_core()
  client.begin_connection().unwrap()
  ignore(client.receive(b"INFO {}\r\n").unwrap())
  let request = client.request("math.add", b"40,2", 10, 5).unwrap()
  ignore(client.drain_outbox())
  let expired = client.expire_requests(15).unwrap()
  assert_eq(expired[0].handle(), request)
}

///|
test "reconnect scenario selects a fallback while first server waits" {
  let planner = @moonnats.reconnect_planner(["a:4222", "b:4222"]).unwrap()
  let first = planner.next(0).unwrap()
  ignore(planner.record_failure(first.url(), 0))
  assert_eq(planner.next(0).unwrap().url(), "b:4222")
}
