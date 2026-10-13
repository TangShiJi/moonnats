///|
test "limits are bounded to positive values" {
  let limits = @moonnats.nats_limits(
    max_control_line=0,
    max_payload=-1,
    max_outbox=0,
  )
  assert_eq(limits.max_control_line(), 1)
  assert_eq(limits.max_payload(), 1)
  assert_eq(limits.max_outbox(), 1)
}

///|
test "server info copies discovered URLs" {
  let urls = ["nats-a:4222", "nats-b:4222"]
  let info = @moonnats.server_info(
    "{\"server_id\":\"s1\"}",
    server_id=Some("s1"),
    headers=true,
    connect_urls=urls,
  )
  urls.push("mutated:4222")
  assert_eq(info.server_id(), Some("s1"))
  assert_eq(info.supports_headers(), true)
  assert_eq(info.connect_urls(), ["nats-a:4222", "nats-b:4222"])
}

///|
test "message preserves binary payload without text conversion" {
  let payload = Bytes::from_array([0x00, 0x0d, 0x0a, 0xff])
  let message = @moonnats.nats_message("binary.data", 9, payload)
  assert_eq(message.subject(), "binary.data")
  assert_eq(message.sid(), 9)
  assert_eq(message.payload(), payload)
}
