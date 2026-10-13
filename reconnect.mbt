///|
pub struct ReconnectPolicy {
  initial_delay : Int
  maximum_delay : Int
  multiplier : Int
  maximum_attempts : Int
} derive(Debug, Eq)

///|
pub fn reconnect_policy(
  initial_delay? : Int = 1,
  maximum_delay? : Int = 60,
  multiplier? : Int = 2,
  maximum_attempts? : Int = 10,
) -> ReconnectPolicy {
  let initial = positive_or_one(initial_delay)
  {
    initial_delay: initial,
    maximum_delay: if maximum_delay < initial {
      initial
    } else {
      maximum_delay
    },
    multiplier: if multiplier < 1 {
      1
    } else {
      multiplier
    },
    maximum_attempts: positive_or_one(maximum_attempts),
  }
}

///|
struct ServerState {
  url : String
  seed : Bool
  mut failures : Int
  mut next_eligible_tick : Int
}

///|
pub struct ServerView {
  url : String
  seed : Bool
  failures : Int
  next_eligible_tick : Int
} derive(Debug, Eq)

///|
pub fn ServerView::url(self : ServerView) -> String {
  self.url
}

///|
pub fn ServerView::is_seed(self : ServerView) -> Bool {
  self.seed
}

///|
pub fn ServerView::failures(self : ServerView) -> Int {
  self.failures
}

///|
pub fn ServerView::next_eligible_tick(self : ServerView) -> Int {
  self.next_eligible_tick
}

///|
pub struct ReconnectPlanner {
  servers : Array[ServerState]
  mut cursor : Int
  policy : ReconnectPolicy
}

///|
pub fn reconnect_planner(
  seeds : Array[String],
  policy? : ReconnectPolicy = reconnect_policy(),
) -> Result[ReconnectPlanner, NatsError] {
  let planner : ReconnectPlanner = { servers: [], cursor: 0, policy }
  for seed in seeds {
    match planner.add_server(seed, seed=true) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  if planner.servers.length() == 0 {
    return Err(
      nats_error(NoServer, "seeds", "at least one seed server is required"),
    )
  }
  Ok(planner)
}

///|
fn valid_server_url(value : String) -> Bool {
  if value.is_empty() || value.contains(" ") || value.contains("\t") {
    return false
  }
  value.contains(":")
}

///|
fn find_server(servers : Array[ServerState], url : String) -> Int {
  for index = 0; index < servers.length(); index = index + 1 {
    if servers[index].url == url {
      return index
    }
  }
  -1
}

///|
pub fn ReconnectPlanner::add_server(
  self : ReconnectPlanner,
  url : String,
  seed? : Bool = false,
) -> Result[Bool, NatsError] {
  if !valid_server_url(url) {
    return Err(
      nats_error(
        NoServer,
        "url",
        "server URL must include host and port without whitespace",
      ),
    )
  }
  let existing = find_server(self.servers, url)
  if existing >= 0 {
    return Ok(false)
  }
  self.servers.push({ url, seed, failures: 0, next_eligible_tick: 0 })
  Ok(true)
}

///|
pub fn ReconnectPlanner::discover(
  self : ReconnectPlanner,
  info : ServerInfo,
) -> Result[Int, NatsError] {
  let mut added = 0
  for url in info.connect_urls() {
    match self.add_server(url) {
      Ok(true) => added = added + 1
      Ok(false) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(added)
}

///|
fn server_view(state : ServerState) -> ServerView {
  {
    url: state.url,
    seed: state.seed,
    failures: state.failures,
    next_eligible_tick: state.next_eligible_tick,
  }
}

///|
pub fn ReconnectPlanner::servers(self : ReconnectPlanner) -> Array[ServerView] {
  let output : Array[ServerView] = []
  for server in self.servers {
    output.push(server_view(server))
  }
  output
}

///|
pub fn ReconnectPlanner::next(
  self : ReconnectPlanner,
  now_tick : Int,
) -> Result[ServerView, NatsError] {
  for offset = 0; offset < self.servers.length(); offset = offset + 1 {
    let index = (self.cursor + offset) % self.servers.length()
    let server = self.servers[index]
    if server.failures < self.policy.maximum_attempts &&
      server.next_eligible_tick <= now_tick {
      self.cursor = (index + 1) % self.servers.length()
      return Ok(server_view(server))
    }
  }
  Err(
    nats_error(
      NoServer,
      "servers",
      "no server is currently eligible for reconnect",
    ),
  )
}

///|
fn capped_backoff(policy : ReconnectPolicy, failures : Int) -> Int {
  let mut delay = policy.initial_delay
  for attempt = 1; attempt < failures; attempt = attempt + 1 {
    if delay >= policy.maximum_delay ||
      delay > policy.maximum_delay / policy.multiplier {
      return policy.maximum_delay
    }
    delay = delay * policy.multiplier
  }
  if delay > policy.maximum_delay {
    policy.maximum_delay
  } else {
    delay
  }
}

///|
/// Records a failed connection. `jitter` is supplied by the caller so tests
/// and embedded targets do not depend on a global random source.
pub fn ReconnectPlanner::record_failure(
  self : ReconnectPlanner,
  url : String,
  now_tick : Int,
  jitter? : Int = 0,
) -> Result[ServerView, NatsError] {
  let index = find_server(self.servers, url)
  if index < 0 {
    return Err(nats_error(NoServer, "url", "cannot fail an unknown server"))
  }
  let server = self.servers[index]
  server.failures = server.failures + 1
  let delay = capped_backoff(self.policy, server.failures)
  let safe_jitter = if jitter < 0 {
    0
  } else if jitter > delay {
    delay
  } else {
    jitter
  }
  let wait = delay + safe_jitter
  server.next_eligible_tick = if now_tick > @int.MAX_VALUE - wait {
    @int.MAX_VALUE
  } else {
    now_tick + wait
  }
  Ok(server_view(server))
}

///|
pub fn ReconnectPlanner::record_success(
  self : ReconnectPlanner,
  url : String,
) -> Result[ServerView, NatsError] {
  let index = find_server(self.servers, url)
  if index < 0 {
    return Err(nats_error(NoServer, "url", "cannot succeed an unknown server"))
  }
  let server = self.servers[index]
  server.failures = 0
  server.next_eligible_tick = 0
  Ok(server_view(server))
}

///|
/// Replays live subscriptions after reconnect without resetting delivery
/// counters. For max-delivery subscriptions only the remaining allowance is
/// sent to the server.
pub fn ClientCore::replay_subscriptions(
  self : ClientCore,
) -> Result[Int, NatsError] {
  match require_connected(self) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let subscriptions = self.subscriptions.list()
  let mut required = 0
  for subscription in subscriptions {
    if subscription.max_messages() is Some(_) {
      required = required + 2
    } else {
      required = required + 1
    }
  }
  if self.outbox.length() + required > self.limits.max_outbox {
    return Err(
      nats_error(
        OutboxFull,
        "outbox",
        "subscription replay exceeds outbox capacity",
      ),
    )
  }
  for subscription in subscriptions {
    let subscribe_frame = match
      encode_subscribe(
        subscription.subject(),
        subscription.sid(),
        queue=subscription.queue(),
      ) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    self.outbox.push(subscribe_frame)
    match subscription.max_messages() {
      Some(maximum) => {
        let remaining = maximum - subscription.delivered()
        if remaining > 0 {
          let frame = match
            encode_unsubscribe(subscription.sid(), max_messages=Some(remaining)) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          self.outbox.push(frame)
        }
      }
      None => ()
    }
  }
  Ok(subscriptions.length())
}
