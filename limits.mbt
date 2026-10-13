///|
/// Resource limits are explicit so an untrusted peer cannot grow memory
/// without bound while a frame is incomplete.
pub struct NatsLimits {
  max_control_line : Int
  max_payload : Int
  max_buffer : Int
  max_headers : Int
  max_subscriptions : Int
  max_outbox : Int
  max_pending_pings : Int
} derive(Debug, Eq)

///|
pub fn nats_limits(
  max_control_line? : Int = 4096,
  max_payload? : Int = 1024 * 1024,
  max_buffer? : Int = 2 * 1024 * 1024,
  max_headers? : Int = 64 * 1024,
  max_subscriptions? : Int = 4096,
  max_outbox? : Int = 1024,
  max_pending_pings? : Int = 2,
) -> NatsLimits {
  {
    max_control_line: positive_or_one(max_control_line),
    max_payload: positive_or_one(max_payload),
    max_buffer: positive_or_one(max_buffer),
    max_headers: positive_or_one(max_headers),
    max_subscriptions: positive_or_one(max_subscriptions),
    max_outbox: positive_or_one(max_outbox),
    max_pending_pings: positive_or_one(max_pending_pings),
  }
}

///|
fn positive_or_one(value : Int) -> Int {
  if value < 1 {
    1
  } else {
    value
  }
}

///|
pub fn NatsLimits::max_control_line(self : NatsLimits) -> Int {
  self.max_control_line
}

///|
pub fn NatsLimits::max_payload(self : NatsLimits) -> Int {
  self.max_payload
}

///|
pub fn NatsLimits::max_buffer(self : NatsLimits) -> Int {
  self.max_buffer
}

///|
pub fn NatsLimits::max_headers(self : NatsLimits) -> Int {
  self.max_headers
}

///|
pub fn NatsLimits::max_subscriptions(self : NatsLimits) -> Int {
  self.max_subscriptions
}

///|
pub fn NatsLimits::max_outbox(self : NatsLimits) -> Int {
  self.max_outbox
}

///|
pub fn NatsLimits::max_pending_pings(self : NatsLimits) -> Int {
  self.max_pending_pings
}
