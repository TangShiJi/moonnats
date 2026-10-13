///|
fn json_escape(value : String) -> String {
  let output = StringBuilder()
  output.write_char('"')
  for char in value.to_array() {
    match char {
      '"' => output.write_string("\\\"")
      '\\' => output.write_string("\\\\")
      '\n' => output.write_string("\\n")
      '\r' => output.write_string("\\r")
      '\t' => output.write_string("\\t")
      _ => output.write_char(char)
    }
  }
  output.write_char('"')
  output.to_string()
}

///|
fn json_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn add_json_field(
  output : StringBuilder,
  first : Bool,
  name : String,
  value : String,
) -> Bool {
  if !first {
    output.write_char(',')
  }
  output.write_string(json_escape(name))
  output.write_char(':')
  output.write_string(value)
  false
}

///|
/// Encodes a deterministic CONNECT frame. Credentials are emitted only when
/// explicitly supplied; no defaults are guessed from the environment.
pub fn encode_connect(options : ConnectOptions) -> Bytes {
  let json = StringBuilder()
  json.write_char('{')
  let mut first = true
  first = add_json_field(json, first, "verbose", json_bool(options.verbose))
  first = add_json_field(json, first, "pedantic", json_bool(options.pedantic))
  first = add_json_field(
    json,
    first,
    "tls_required",
    json_bool(options.tls_required),
  )
  first = add_json_field(json, first, "protocol", options.protocol.to_string())
  first = add_json_field(json, first, "echo", json_bool(options.echo))
  first = add_json_field(json, first, "headers", json_bool(options.headers))
  first = add_json_field(
    json,
    first,
    "no_responders",
    json_bool(options.no_responders),
  )
  first = add_json_field(json, first, "lang", json_escape(options.lang))
  first = add_json_field(json, first, "version", json_escape(options.version))
  match options.name {
    Some(value) =>
      first = add_json_field(json, first, "name", json_escape(value))
    None => ()
  }
  match options.user {
    Some(value) =>
      first = add_json_field(json, first, "user", json_escape(value))
    None => ()
  }
  match options.password {
    Some(value) =>
      first = add_json_field(json, first, "pass", json_escape(value))
    None => ()
  }
  match options.auth_token {
    Some(value) =>
      first = add_json_field(json, first, "auth_token", json_escape(value))
    None => ()
  }
  ignore(first)
  json.write_char('}')
  bytes_from_text("CONNECT " + json.to_string() + "\r\n")
}

///|
fn validate_payload(
  payload : Bytes,
  limits : NatsLimits,
) -> Result[Unit, NatsError] {
  if payload.length() > limits.max_payload {
    Err(
      nats_error(
        PayloadTooLarge,
        "payload",
        "payload exceeds configured client limit",
      ),
    )
  } else {
    Ok(())
  }
}

///|
/// Encodes a binary-safe PUB command.
pub fn encode_publish(
  subject : String,
  payload : Bytes,
  reply_to? : String? = None,
  limits? : NatsLimits = nats_limits(),
) -> Result[Bytes, NatsError] {
  match validate_publish_subject(subject) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match reply_to {
    Some(reply) =>
      match validate_publish_subject(reply) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    None => ()
  }
  match validate_payload(payload, limits) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let line = match reply_to {
    Some(reply) =>
      "PUB " +
      subject +
      " " +
      reply +
      " " +
      payload.length().to_string() +
      "\r\n"
    None => "PUB " + subject + " " + payload.length().to_string() + "\r\n"
  }
  Ok(bytes_concat([bytes_from_text(line), payload, b"\r\n"]))
}

///|
/// Encodes HPUB with exact byte lengths for the header and combined payload.
pub fn encode_header_publish(
  subject : String,
  headers : NatsHeaders,
  payload : Bytes,
  reply_to? : String? = None,
  limits? : NatsLimits = nats_limits(),
) -> Result[Bytes, NatsError] {
  match validate_publish_subject(subject) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match reply_to {
    Some(reply) =>
      match validate_publish_subject(reply) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    None => ()
  }
  let header_bytes = match encode_headers(headers) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if header_bytes.length() > limits.max_headers {
    return Err(
      nats_error(
        FrameTooLarge,
        "headers",
        "header section exceeds configured limit",
      ),
    )
  }
  let total = header_bytes.length() + payload.length()
  if total > limits.max_payload {
    return Err(
      nats_error(
        PayloadTooLarge,
        "payload",
        "headers and payload exceed configured limit",
      ),
    )
  }
  let sizes = header_bytes.length().to_string() + " " + total.to_string()
  let line = match reply_to {
    Some(reply) => "HPUB " + subject + " " + reply + " " + sizes + "\r\n"
    None => "HPUB " + subject + " " + sizes + "\r\n"
  }
  Ok(bytes_concat([bytes_from_text(line), header_bytes, payload, b"\r\n"]))
}

///|
pub fn encode_subscribe(
  subject : String,
  sid : Int,
  queue? : String? = None,
) -> Result[Bytes, NatsError] {
  match validate_subscription_subject(subject) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if sid < 1 {
    return Err(
      nats_error(InvalidSid, "sid", "subscription id must be positive"),
    )
  }
  match queue {
    Some(value) =>
      match validate_queue_group(value) {
        Ok(_) =>
          Ok(
            bytes_from_text(
              "SUB " + subject + " " + value + " " + sid.to_string() + "\r\n",
            ),
          )
        Err(error) => Err(error)
      }
    None =>
      Ok(bytes_from_text("SUB " + subject + " " + sid.to_string() + "\r\n"))
  }
}

///|
pub fn encode_unsubscribe(
  sid : Int,
  max_messages? : Int? = None,
) -> Result[Bytes, NatsError] {
  if sid < 1 {
    return Err(
      nats_error(InvalidSid, "sid", "subscription id must be positive"),
    )
  }
  match max_messages {
    Some(value) if value < 1 =>
      Err(
        nats_error(
          InvalidInteger,
          "max_messages",
          "maximum messages must be positive",
        ),
      )
    Some(value) =>
      Ok(
        bytes_from_text(
          "UNSUB " + sid.to_string() + " " + value.to_string() + "\r\n",
        ),
      )
    None => Ok(bytes_from_text("UNSUB " + sid.to_string() + "\r\n"))
  }
}

///|
pub fn encode_ping() -> Bytes {
  b"PING\r\n"
}

///|
pub fn encode_pong() -> Bytes {
  b"PONG\r\n"
}
