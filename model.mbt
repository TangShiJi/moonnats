///|
/// Information advertised by an `INFO` frame. Unknown JSON fields remain in
/// `raw_json`, allowing forward-compatible inspection without weakening the
/// stable accessors used by client policy.
pub struct ServerInfo {
  raw_json : String
  server_id : String?
  server_name : String?
  version : String?
  host : String?
  port : Int?
  headers : Bool
  max_payload : Int?
  proto : Int
  auth_required : Bool
  tls_required : Bool
  connect_urls : Array[String]
  nonce : String?
  lame_duck_mode : Bool
} derive(Debug, Eq)

///|
pub fn server_info(
  raw_json : String,
  server_id? : String? = None,
  server_name? : String? = None,
  version? : String? = None,
  host? : String? = None,
  port? : Int? = None,
  headers? : Bool = false,
  max_payload? : Int? = None,
  proto? : Int = 0,
  auth_required? : Bool = false,
  tls_required? : Bool = false,
  connect_urls? : Array[String] = [],
  nonce? : String? = None,
  lame_duck_mode? : Bool = false,
) -> ServerInfo {
  {
    raw_json,
    server_id,
    server_name,
    version,
    host,
    port,
    headers,
    max_payload,
    proto,
    auth_required,
    tls_required,
    connect_urls: connect_urls.copy(),
    nonce,
    lame_duck_mode,
  }
}

///|
pub fn ServerInfo::raw_json(self : ServerInfo) -> String {
  self.raw_json
}

///|
pub fn ServerInfo::server_id(self : ServerInfo) -> String? {
  self.server_id
}

///|
pub fn ServerInfo::server_name(self : ServerInfo) -> String? {
  self.server_name
}

///|
pub fn ServerInfo::version(self : ServerInfo) -> String? {
  self.version
}

///|
pub fn ServerInfo::host(self : ServerInfo) -> String? {
  self.host
}

///|
pub fn ServerInfo::port(self : ServerInfo) -> Int? {
  self.port
}

///|
pub fn ServerInfo::supports_headers(self : ServerInfo) -> Bool {
  self.headers
}

///|
pub fn ServerInfo::max_payload(self : ServerInfo) -> Int? {
  self.max_payload
}

///|
pub fn ServerInfo::protocol_version(self : ServerInfo) -> Int {
  self.proto
}

///|
pub fn ServerInfo::auth_required(self : ServerInfo) -> Bool {
  self.auth_required
}

///|
pub fn ServerInfo::tls_required(self : ServerInfo) -> Bool {
  self.tls_required
}

///|
pub fn ServerInfo::connect_urls(self : ServerInfo) -> Array[String] {
  self.connect_urls.copy()
}

///|
pub fn ServerInfo::nonce(self : ServerInfo) -> String? {
  self.nonce
}

///|
pub fn ServerInfo::lame_duck_mode(self : ServerInfo) -> Bool {
  self.lame_duck_mode
}

///|
/// Options serialized into the client `CONNECT` frame. Passwords and tokens
/// are intentionally not exposed through Debug-derived output.
pub struct ConnectOptions {
  verbose : Bool
  pedantic : Bool
  tls_required : Bool
  name : String?
  user : String?
  password : String?
  auth_token : String?
  protocol : Int
  echo : Bool
  headers : Bool
  no_responders : Bool
  lang : String
  version : String
}

///|
pub fn connect_options(
  verbose? : Bool = false,
  pedantic? : Bool = false,
  tls_required? : Bool = false,
  name? : String? = None,
  user? : String? = None,
  password? : String? = None,
  auth_token? : String? = None,
  protocol? : Int = 1,
  echo? : Bool = true,
  headers? : Bool = true,
  no_responders? : Bool = true,
  lang? : String = "moonbit",
  version? : String = "0.1.0",
) -> ConnectOptions {
  {
    verbose,
    pedantic,
    tls_required,
    name,
    user,
    password,
    auth_token,
    protocol,
    echo,
    headers,
    no_responders,
    lang,
    version,
  }
}

///|
pub struct NatsMessage {
  subject : String
  sid : Int
  reply_to : String?
  headers : NatsHeaders?
  payload : Bytes
} derive(Debug, Eq)

///|
pub fn nats_message(
  subject : String,
  sid : Int,
  payload : Bytes,
  reply_to? : String? = None,
  headers? : NatsHeaders? = None,
) -> NatsMessage {
  { subject, sid, reply_to, headers, payload }
}

///|
pub fn NatsMessage::subject(self : NatsMessage) -> String {
  self.subject
}

///|
pub fn NatsMessage::sid(self : NatsMessage) -> Int {
  self.sid
}

///|
pub fn NatsMessage::reply_to(self : NatsMessage) -> String? {
  self.reply_to
}

///|
pub fn NatsMessage::headers(self : NatsMessage) -> NatsHeaders? {
  self.headers
}

///|
pub fn NatsMessage::payload(self : NatsMessage) -> Bytes {
  self.payload
}

///|
/// Complete server operations emitted by the incremental decoder.
pub(all) enum ServerOp {
  Info(ServerInfo)
  Message(NatsMessage)
  Ping
  Pong
  OkFrame
  ServerError(String)
} derive(Debug, Eq)
