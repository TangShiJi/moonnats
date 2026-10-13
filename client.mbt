///|
pub(all) enum ClientState {
  Disconnected
  AwaitingInfo
  Connected
  Draining
  Closed
} derive(Debug, Eq)

///|
pub(all) enum ClientEvent {
  ServerInformation(ServerInfo)
  Delivered(DispatchResult)
  ServerAcknowledged
  ServerFailure(String)
  FlushCompleted
  KeepAliveReplied
} derive(Debug, Eq)

///|
/// Sans-I/O client core. A transport adapter feeds received bytes into
/// `receive` and writes frames returned by `drain_outbox` to TCP or WebSocket.
pub struct ClientCore {
  mut state : ClientState
  decoder : ProtocolDecoder
  subscriptions : SubscriptionRegistry
  mut outbox : Array[Bytes]
  mut next_sid : Int
  mut pending_pings : Int
  mut pending_requests : Array[PendingRequestState]
  mut request_sequence : Int
  mut server : ServerInfo?
  limits : NatsLimits
}

///|
pub fn client_core(limits? : NatsLimits = nats_limits()) -> ClientCore {
  {
    state: Disconnected,
    decoder: protocol_decoder(limits~),
    subscriptions: subscription_registry(limits~),
    outbox: [],
    next_sid: 1,
    pending_pings: 0,
    pending_requests: [],
    request_sequence: 1,
    server: None,
    limits,
  }
}

///|
pub fn ClientCore::state(self : ClientCore) -> ClientState {
  self.state
}

///|
pub fn ClientCore::server_info(self : ClientCore) -> ServerInfo? {
  self.server
}

///|
pub fn ClientCore::pending_pings(self : ClientCore) -> Int {
  self.pending_pings
}

///|
pub fn ClientCore::pending_request_count(self : ClientCore) -> Int {
  self.pending_requests.length()
}

///|
pub fn ClientCore::outbox_length(self : ClientCore) -> Int {
  self.outbox.length()
}

///|
pub fn ClientCore::subscriptions(self : ClientCore) -> Array[SubscriptionView] {
  self.subscriptions.list()
}

///|
pub fn ClientCore::begin_connection(
  self : ClientCore,
) -> Result[Unit, NatsError] {
  match self.state {
    Closed =>
      Err(nats_error(InvalidState, "state", "closed client cannot reconnect"))
    _ => {
      self.decoder.reset()
      self.outbox = []
      self.pending_pings = 0
      self.server = None
      self.state = AwaitingInfo
      Ok(())
    }
  }
}

///|
pub fn ClientCore::mark_disconnected(self : ClientCore) -> Unit {
  if self.state is Closed {
    return
  }
  self.decoder.reset()
  self.outbox = []
  self.pending_pings = 0
  self.server = None
  self.state = Disconnected
}

///|
pub fn ClientCore::close(self : ClientCore) -> Unit {
  self.decoder.reset()
  self.outbox = []
  self.pending_pings = 0
  self.server = None
  self.state = Closed
}

///|
fn require_connected(client : ClientCore) -> Result[Unit, NatsError] {
  if client.state is Connected {
    Ok(())
  } else {
    Err(
      nats_error(InvalidState, "state", "operation requires a connected client"),
    )
  }
}

///|
fn ClientCore::enqueue(
  self : ClientCore,
  frame : Bytes,
) -> Result[Unit, NatsError] {
  if self.outbox.length() >= self.limits.max_outbox {
    Err(nats_error(OutboxFull, "outbox", "outbound frame limit reached"))
  } else {
    self.outbox.push(frame)
    Ok(())
  }
}

///|
fn ClientCore::enqueue_pair(
  self : ClientCore,
  first : Bytes,
  second : Bytes,
) -> Result[Unit, NatsError] {
  if self.outbox.length() + 2 > self.limits.max_outbox {
    Err(nats_error(OutboxFull, "outbox", "outbound frame limit reached"))
  } else {
    self.outbox.push(first)
    self.outbox.push(second)
    Ok(())
  }
}

///|
pub fn ClientCore::send_connect(
  self : ClientCore,
  options : ConnectOptions,
) -> Result[Unit, NatsError] {
  match require_connected(self) {
    Ok(_) => self.enqueue(encode_connect(options))
    Err(error) => Err(error)
  }
}

///|
pub fn ClientCore::publish(
  self : ClientCore,
  subject : String,
  payload : Bytes,
  reply_to? : String? = None,
) -> Result[Unit, NatsError] {
  match require_connected(self) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let frame = match
    encode_publish(subject, payload, reply_to~, limits=self.limits) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.enqueue(frame)
}

///|
pub fn ClientCore::publish_with_headers(
  self : ClientCore,
  subject : String,
  headers : NatsHeaders,
  payload : Bytes,
  reply_to? : String? = None,
) -> Result[Unit, NatsError] {
  match require_connected(self) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match self.server {
    Some(info) if !info.supports_headers() =>
      return Err(
        nats_error(
          InvalidState,
          "headers",
          "server did not advertise header support",
        ),
      )
    _ => ()
  }
  let frame = match
    encode_header_publish(
      subject,
      headers,
      payload,
      reply_to~,
      limits=self.limits,
    ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  self.enqueue(frame)
}

///|
pub fn ClientCore::subscribe(
  self : ClientCore,
  subject : String,
  queue? : String? = None,
  max_messages? : Int? = None,
) -> Result[Int, NatsError] {
  match require_connected(self) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let sid = self.next_sid
  let subscribe_frame = match encode_subscribe(subject, sid, queue~) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let unsubscribe_frame = match max_messages {
    Some(value) =>
      match encode_unsubscribe(sid, max_messages=Some(value)) {
        Ok(frame) => Some(frame)
        Err(error) => return Err(error)
      }
    None => None
  }
  match self.subscriptions.add(sid, subject, queue~, max_messages~) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let queued = match unsubscribe_frame {
    Some(frame) => self.enqueue_pair(subscribe_frame, frame)
    None => self.enqueue(subscribe_frame)
  }
  match queued {
    Ok(_) => {
      self.next_sid = self.next_sid + 1
      Ok(sid)
    }
    Err(error) => {
      ignore(self.subscriptions.remove(sid))
      Err(error)
    }
  }
}

///|
pub fn ClientCore::unsubscribe(
  self : ClientCore,
  sid : Int,
) -> Result[SubscriptionView, NatsError] {
  match require_connected(self) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if self.subscriptions.get(sid) is None {
    return Err(
      nats_error(
        UnknownSubscription,
        "sid",
        "subscription id is not registered",
      ),
    )
  }
  let frame = match encode_unsubscribe(sid) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.enqueue(frame) {
    Ok(_) => self.subscriptions.remove(sid)
    Err(error) => Err(error)
  }
}

///|
/// Queues PING as an observable flush barrier.
pub fn ClientCore::flush(self : ClientCore) -> Result[Unit, NatsError] {
  match require_connected(self) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if self.pending_pings >= self.limits.max_pending_pings {
    return Err(
      nats_error(
        RequestLimitExceeded,
        "pending_pings",
        "too many unanswered PING frames",
      ),
    )
  }
  match self.enqueue(encode_ping()) {
    Ok(_) => {
      self.pending_pings = self.pending_pings + 1
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///|
pub fn ClientCore::drain_outbox(self : ClientCore) -> Array[Bytes] {
  let frames = self.outbox
  self.outbox = []
  frames
}

///|
fn ClientCore::handle_operation(
  self : ClientCore,
  operation : ServerOp,
) -> Result[ClientEvent?, NatsError] {
  match operation {
    Info(info) => {
      if self.state is Closed || self.state is Disconnected {
        return Err(
          nats_error(
            InvalidState,
            "INFO",
            "INFO received without an active connection",
          ),
        )
      }
      self.server = Some(info)
      self.state = Connected
      Ok(Some(ServerInformation(info)))
    }
    Message(message) => {
      complete_pending_request(self, message.sid)
      let delivered = match self.subscriptions.dispatch(message) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      Ok(Some(Delivered(delivered)))
    }
    Ping =>
      match self.enqueue(encode_pong()) {
        Ok(_) => Ok(Some(KeepAliveReplied))
        Err(error) => Err(error)
      }
    Pong =>
      if self.pending_pings > 0 {
        self.pending_pings = self.pending_pings - 1
        Ok(Some(FlushCompleted))
      } else {
        Ok(None)
      }
    OkFrame => Ok(Some(ServerAcknowledged))
    ServerError(message) => Ok(Some(ServerFailure(message)))
  }
}

///|
pub fn ClientCore::receive(
  self : ClientCore,
  chunk : Bytes,
) -> Result[Array[ClientEvent], NatsError] {
  if self.state is Disconnected || self.state is Closed {
    return Err(
      nats_error(
        InvalidState,
        "state",
        "cannot receive bytes while disconnected",
      ),
    )
  }
  let operations = match self.decoder.push(chunk) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let events : Array[ClientEvent] = []
  for operation in operations {
    match self.handle_operation(operation) {
      Ok(Some(event)) => events.push(event)
      Ok(None) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(events)
}
