///|
struct PendingRequestState {
  sid : Int
  request_subject : String
  inbox : String
  deadline_tick : Int
}

///|
pub struct RequestHandle {
  sid : Int
  request_subject : String
  inbox : String
  deadline_tick : Int
} derive(Debug, Eq)

///|
pub fn RequestHandle::sid(self : RequestHandle) -> Int {
  self.sid
}

///|
pub fn RequestHandle::request_subject(self : RequestHandle) -> String {
  self.request_subject
}

///|
pub fn RequestHandle::inbox(self : RequestHandle) -> String {
  self.inbox
}

///|
pub fn RequestHandle::deadline_tick(self : RequestHandle) -> Int {
  self.deadline_tick
}

///|
pub struct ExpiredRequest {
  handle : RequestHandle
} derive(Debug, Eq)

///|
pub fn ExpiredRequest::handle(self : ExpiredRequest) -> RequestHandle {
  self.handle
}

///|
fn request_handle(state : PendingRequestState) -> RequestHandle {
  {
    sid: state.sid,
    request_subject: state.request_subject,
    inbox: state.inbox,
    deadline_tick: state.deadline_tick,
  }
}

///|
fn complete_pending_request(client : ClientCore, sid : Int) -> Unit {
  let remaining : Array[PendingRequestState] = []
  for request in client.pending_requests {
    if request.sid != sid {
      remaining.push(request)
    }
  }
  client.pending_requests = remaining
}

///|
/// Builds the canonical NATS request/reply sequence atomically: SUB inbox,
/// UNSUB after one response, then PUB with the inbox as reply subject.
pub fn ClientCore::request(
  self : ClientCore,
  subject : String,
  payload : Bytes,
  now_tick : Int,
  timeout_ticks : Int,
  inbox_prefix? : String = "_INBOX.moonnats",
) -> Result[RequestHandle, NatsError] {
  match require_connected(self) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if timeout_ticks < 1 {
    return Err(
      nats_error(
        InvalidInteger,
        "timeout_ticks",
        "request timeout must be positive",
      ),
    )
  }
  if self.pending_requests.length() >= self.limits.max_subscriptions {
    return Err(
      nats_error(
        RequestLimitExceeded,
        "requests",
        "pending request limit reached",
      ),
    )
  }
  if self.outbox.length() + 3 > self.limits.max_outbox {
    return Err(
      nats_error(OutboxFull, "outbox", "request requires three outbound frames"),
    )
  }
  let inbox = match inbox_subject(inbox_prefix, self.request_sequence) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let sid = self.next_sid
  let subscribe_frame = match encode_subscribe(inbox, sid) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let unsubscribe_frame = match encode_unsubscribe(sid, max_messages=Some(1)) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let publish_frame = match
    encode_publish(subject, payload, reply_to=Some(inbox), limits=self.limits) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.subscriptions.add(sid, inbox, max_messages=Some(1)) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let deadline_tick = if now_tick > @int.MAX_VALUE - timeout_ticks {
    @int.MAX_VALUE
  } else {
    now_tick + timeout_ticks
  }
  let state : PendingRequestState = {
    sid,
    request_subject: subject,
    inbox,
    deadline_tick,
  }
  self.pending_requests.push(state)
  self.outbox.push(subscribe_frame)
  self.outbox.push(unsubscribe_frame)
  self.outbox.push(publish_frame)
  self.next_sid = self.next_sid + 1
  self.request_sequence = self.request_sequence + 1
  Ok(request_handle(state))
}

///|
pub fn ClientCore::pending_requests(self : ClientCore) -> Array[RequestHandle] {
  let output : Array[RequestHandle] = []
  for request in self.pending_requests {
    output.push(request_handle(request))
  }
  output
}

///|
/// Expires requests using a caller-owned monotonic tick. The core never reads
/// wall-clock time, which keeps behavior deterministic in tests and on wasm.
pub fn ClientCore::expire_requests(
  self : ClientCore,
  now_tick : Int,
) -> Result[Array[ExpiredRequest], NatsError] {
  let expired_states : Array[PendingRequestState] = []
  for request in self.pending_requests {
    if request.deadline_tick <= now_tick {
      expired_states.push(request)
    }
  }
  if self.state is Connected &&
    self.outbox.length() + expired_states.length() > self.limits.max_outbox {
    return Err(
      nats_error(
        OutboxFull,
        "outbox",
        "cannot queue request cancellation frames",
      ),
    )
  }
  let expired : Array[ExpiredRequest] = []
  for request in expired_states {
    if self.state is Connected {
      let frame = match encode_unsubscribe(request.sid) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      self.outbox.push(frame)
    }
    if self.subscriptions.get(request.sid) is Some(_) {
      ignore(self.subscriptions.remove(request.sid))
    }
    expired.push({ handle: request_handle(request) })
    complete_pending_request(self, request.sid)
  }
  Ok(expired)
}
