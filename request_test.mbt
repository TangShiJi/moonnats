///|
fn request_client(
  limits? : @moonnats.NatsLimits = @moonnats.nats_limits(),
) -> @moonnats.ClientCore {
  let client = @moonnats.client_core(limits~)
  client.begin_connection().unwrap()
  ignore(client.receive(b"INFO {}\r\n").unwrap())
  client
}

///|
test "request builds subscribe auto-unsubscribe and publish frames" {
  let client = request_client()
  let handle = client.request("math.add", b"1,2", 100, 20).unwrap()
  assert_eq(handle.sid(), 1)
  assert_eq(handle.inbox(), "_INBOX.moonnats.1")
  assert_eq(handle.deadline_tick(), 120)
  let frames = client.drain_outbox()
  assert_eq(frames.length(), 3)
  assert_eq(@utf8.decode_lossy(frames[0][:]), "SUB _INBOX.moonnats.1 1\r\n")
  assert_eq(@utf8.decode_lossy(frames[1][:]), "UNSUB 1 1\r\n")
  assert_eq(
    @utf8.decode_lossy(frames[2][:]),
    "PUB math.add _INBOX.moonnats.1 3\r\n1,2\r\n",
  )
}

///|
test "response completes request and normal delivery accounting" {
  let client = request_client()
  ignore(client.request("math.add", b"1,2", 0, 10).unwrap())
  ignore(client.drain_outbox())
  let events = client.receive(b"MSG _INBOX.moonnats.1 1 1\r\n3\r\n").unwrap()
  assert_true(events[0] is Delivered(_))
  assert_eq(client.pending_request_count(), 0)
  assert_eq(client.subscriptions(), [])
}

///|
test "expiration queues cancellation and returns handles" {
  let client = request_client()
  let first = client.request("slow.one", b"", 10, 5).unwrap()
  let second = client.request("slow.two", b"", 10, 50).unwrap()
  ignore(client.drain_outbox())
  let expired = client.expire_requests(15).unwrap()
  assert_eq(expired.length(), 1)
  assert_eq(expired[0].handle(), first)
  assert_eq(client.pending_requests(), [second])
  assert_eq(@utf8.decode_lossy(client.drain_outbox()[0][:]), "UNSUB 1\r\n")
}

///|
test "request validates timeout before mutating state" {
  let client = request_client()
  assert_true(
    client.request("work", b"", 0, 0) is Err({ kind: InvalidInteger, .. }),
  )
  assert_eq(client.pending_request_count(), 0)
  assert_eq(client.outbox_length(), 0)
}

///|
test "request is atomic when outbox cannot hold all frames" {
  let limits = @moonnats.nats_limits(max_outbox=2)
  let client = request_client(limits~)
  assert_true(
    client.request("work", b"x", 0, 10) is Err({ kind: OutboxFull, .. }),
  )
  assert_eq(client.pending_request_count(), 0)
  assert_eq(client.subscriptions(), [])
}
