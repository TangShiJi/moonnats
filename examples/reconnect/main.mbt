///|
fn main {
  let policy = @moonnats.reconnect_policy(
    initial_delay=2,
    maximum_delay=30,
    multiplier=2,
  )
  let planner = @moonnats.reconnect_planner(
    ["nats-a.example:4222", "nats-b.example:4222"],
    policy~,
  ).unwrap()
  let first = planner.next(0).unwrap()
  println("try=" + first.url())
  let failed = planner.record_failure(first.url(), 0, jitter=1).unwrap()
  println("retry_at=" + failed.next_eligible_tick().to_string())
  println("fallback=" + planner.next(0).unwrap().url())
}
