///|
test "registry adds queue subscription and returns snapshots" {
  let registry = @moonnats.subscription_registry()
  let added = registry.add(1, "jobs.*", queue=Some("workers")).unwrap()
  assert_eq(added.sid(), 1)
  assert_eq(added.queue(), Some("workers"))
  assert_eq(registry.length(), 1)
  assert_eq(registry.list(), [added])
}

///|
test "registry rejects duplicate and excessive subscriptions" {
  let limits = @moonnats.nats_limits(max_subscriptions=1)
  let registry = @moonnats.subscription_registry(limits~)
  ignore(registry.add(1, "events"))
  assert_true(
    registry.add(1, "events") is Err({ kind: DuplicateSubscription, .. }),
  )
  assert_true(
    registry.add(2, "events") is Err({ kind: RequestLimitExceeded, .. }),
  )
}

///|
test "dispatch verifies subject and accounts delivery" {
  let registry = @moonnats.subscription_registry()
  ignore(registry.add(4, "orders.*"))
  let message = @moonnats.nats_message("orders.created", 4, b"one")
  let delivered = registry.dispatch(message).unwrap()
  assert_eq(delivered.subscription().delivered(), 1)
  assert_false(delivered.auto_unsubscribed())
  assert_eq(registry.get(4).unwrap().delivered(), 1)
  assert_true(
    registry.dispatch(@moonnats.nats_message("users.created", 4, b"bad"))
    is Err({ kind: ProtocolViolation, .. }),
  )
}

///|
test "max messages automatically removes subscription" {
  let registry = @moonnats.subscription_registry()
  ignore(registry.add(9, "once", max_messages=Some(2)))
  assert_false(
    registry
    .dispatch(@moonnats.nats_message("once", 9, b"a"))
    .unwrap()
    .auto_unsubscribed(),
  )
  assert_true(
    registry
    .dispatch(@moonnats.nats_message("once", 9, b"b"))
    .unwrap()
    .auto_unsubscribed(),
  )
  assert_eq(registry.get(9), None)
}

///|
test "unknown sid is explicit and removal is deterministic" {
  let registry = @moonnats.subscription_registry()
  assert_true(
    registry.dispatch(@moonnats.nats_message("events", 88, b"x"))
    is Err({ kind: UnknownSubscription, .. }),
  )
  ignore(registry.add(2, "events"))
  assert_eq(registry.remove(2).unwrap().subject(), "events")
  assert_true(registry.remove(2) is Err({ kind: UnknownSubscription, .. }))
}
