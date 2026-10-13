///|
struct SubscriptionState {
  sid : Int
  subject : String
  queue : String?
  max_messages : Int?
  mut delivered : Int
}

///|
/// Immutable snapshot exposed to applications and diagnostics.
pub struct SubscriptionView {
  sid : Int
  subject : String
  queue : String?
  max_messages : Int?
  delivered : Int
} derive(Debug, Eq)

///|
pub fn SubscriptionView::sid(self : SubscriptionView) -> Int {
  self.sid
}

///|
pub fn SubscriptionView::subject(self : SubscriptionView) -> String {
  self.subject
}

///|
pub fn SubscriptionView::queue(self : SubscriptionView) -> String? {
  self.queue
}

///|
pub fn SubscriptionView::max_messages(self : SubscriptionView) -> Int? {
  self.max_messages
}

///|
pub fn SubscriptionView::delivered(self : SubscriptionView) -> Int {
  self.delivered
}

///|
pub struct DispatchResult {
  subscription : SubscriptionView
  message : NatsMessage
  auto_unsubscribed : Bool
} derive(Debug, Eq)

///|
pub fn DispatchResult::subscription(self : DispatchResult) -> SubscriptionView {
  self.subscription
}

///|
pub fn DispatchResult::message(self : DispatchResult) -> NatsMessage {
  self.message
}

///|
pub fn DispatchResult::auto_unsubscribed(self : DispatchResult) -> Bool {
  self.auto_unsubscribed
}

///|
/// Tracks SIDs independently of any socket runtime. The NATS server performs
/// queue-group selection; this registry verifies and accounts for deliveries.
pub struct SubscriptionRegistry {
  mut subscriptions : Array[SubscriptionState]
  limits : NatsLimits
}

///|
pub fn subscription_registry(
  limits? : NatsLimits = nats_limits(),
) -> SubscriptionRegistry {
  { subscriptions: [], limits }
}

///|
fn subscription_view(value : SubscriptionState) -> SubscriptionView {
  {
    sid: value.sid,
    subject: value.subject,
    queue: value.queue,
    max_messages: value.max_messages,
    delivered: value.delivered,
  }
}

///|
fn find_subscription_index(items : Array[SubscriptionState], sid : Int) -> Int {
  for index = 0; index < items.length(); index = index + 1 {
    if items[index].sid == sid {
      return index
    }
  }
  -1
}

///|
pub fn SubscriptionRegistry::length(self : SubscriptionRegistry) -> Int {
  self.subscriptions.length()
}

///|
pub fn SubscriptionRegistry::list(
  self : SubscriptionRegistry,
) -> Array[SubscriptionView] {
  let output : Array[SubscriptionView] = []
  for subscription in self.subscriptions {
    output.push(subscription_view(subscription))
  }
  output
}

///|
pub fn SubscriptionRegistry::get(
  self : SubscriptionRegistry,
  sid : Int,
) -> SubscriptionView? {
  let index = find_subscription_index(self.subscriptions, sid)
  if index < 0 {
    None
  } else {
    Some(subscription_view(self.subscriptions[index]))
  }
}

///|
pub fn SubscriptionRegistry::add(
  self : SubscriptionRegistry,
  sid : Int,
  subject : String,
  queue? : String? = None,
  max_messages? : Int? = None,
) -> Result[SubscriptionView, NatsError] {
  if sid < 1 {
    return Err(
      nats_error(InvalidSid, "sid", "subscription id must be positive"),
    )
  }
  match validate_subscription_subject(subject) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match queue {
    Some(value) =>
      match validate_queue_group(value) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    None => ()
  }
  match max_messages {
    Some(value) if value < 1 =>
      return Err(
        nats_error(
          InvalidInteger,
          "max_messages",
          "maximum messages must be positive",
        ),
      )
    _ => ()
  }
  if find_subscription_index(self.subscriptions, sid) >= 0 {
    return Err(
      nats_error(
        DuplicateSubscription,
        "sid",
        "subscription id is already registered",
      ),
    )
  }
  if self.subscriptions.length() >= self.limits.max_subscriptions {
    return Err(
      nats_error(
        RequestLimitExceeded,
        "subscriptions",
        "subscription limit reached",
      ),
    )
  }
  let state : SubscriptionState = {
    sid,
    subject,
    queue,
    max_messages,
    delivered: 0,
  }
  self.subscriptions.push(state)
  Ok(subscription_view(state))
}

///|
pub fn SubscriptionRegistry::remove(
  self : SubscriptionRegistry,
  sid : Int,
) -> Result[SubscriptionView, NatsError] {
  let index = find_subscription_index(self.subscriptions, sid)
  if index < 0 {
    return Err(
      nats_error(
        UnknownSubscription,
        "sid",
        "subscription id is not registered",
      ),
    )
  }
  let removed = subscription_view(self.subscriptions[index])
  let next : Array[SubscriptionState] = []
  for item_index = 0
      item_index < self.subscriptions.length()
      item_index = item_index + 1 {
    if item_index != index {
      next.push(self.subscriptions[item_index])
    }
  }
  self.subscriptions = next
  Ok(removed)
}

///|
pub fn SubscriptionRegistry::dispatch(
  self : SubscriptionRegistry,
  message : NatsMessage,
) -> Result[DispatchResult, NatsError] {
  let index = find_subscription_index(self.subscriptions, message.sid)
  if index < 0 {
    return Err(
      nats_error(
        UnknownSubscription,
        "sid",
        "message references an unknown subscription",
      ),
    )
  }
  let state = self.subscriptions[index]
  let matches = match subject_matches(state.subject, message.subject) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !matches {
    return Err(
      nats_error(
        ProtocolViolation,
        "subject",
        "message subject does not match subscription",
      ),
    )
  }
  state.delivered = state.delivered + 1
  let reached_limit = match state.max_messages {
    Some(limit) => state.delivered >= limit
    None => false
  }
  let view = subscription_view(state)
  if reached_limit {
    ignore(self.remove(state.sid))
  }
  Ok({ subscription: view, message, auto_unsubscribed: reached_limit })
}
