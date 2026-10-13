///|
test "publish subjects reject wildcards and empty tokens" {
  assert_eq(@moonnats.validate_publish_subject("orders.created"), Ok(()))
  assert_true(@moonnats.validate_publish_subject("orders.*") is Err(_))
  assert_true(@moonnats.validate_publish_subject("orders..created") is Err(_))
}

///|
test "subscription wildcards follow NATS token rules" {
  assert_eq(@moonnats.validate_subscription_subject("orders.*"), Ok(()))
  assert_eq(@moonnats.validate_subscription_subject("orders.>"), Ok(()))
  assert_true(
    @moonnats.validate_subscription_subject("orders.>.audit") is Err(_),
  )
  assert_true(@moonnats.validate_subscription_subject("orders.foo*") is Err(_))
}

///|
test "subject matching distinguishes one and tail wildcards" {
  assert_eq(@moonnats.subject_matches("orders.*", "orders.created"), Ok(true))
  assert_eq(
    @moonnats.subject_matches("orders.*", "orders.eu.created"),
    Ok(false),
  )
  assert_eq(
    @moonnats.subject_matches("orders.>", "orders.eu.created"),
    Ok(true),
  )
  assert_eq(@moonnats.subject_matches("orders.>", "orders"), Ok(false))
}

///|
test "queue and inbox validation produce structured errors" {
  let queue_error = @moonnats.validate_queue_group("worker pool")
  assert_true(queue_error is Err({ kind: InvalidQueueGroup, .. }))
  assert_eq(@moonnats.inbox_subject("_INBOX.moon", 7), Ok("_INBOX.moon.7"))
}
