///|
/// Stateful streaming parser. Callers may feed arbitrary transport chunks;
/// complete frames are emitted while an incomplete suffix remains buffered.
pub struct ProtocolDecoder {
  mut buffer : Array[Byte]
  limits : NatsLimits
}

///|
pub fn protocol_decoder(
  limits? : NatsLimits = nats_limits(),
) -> ProtocolDecoder {
  { buffer: [], limits }
}

///|
pub fn ProtocolDecoder::buffered_bytes(self : ProtocolDecoder) -> Int {
  self.buffer.length()
}

///|
pub fn ProtocolDecoder::reset(self : ProtocolDecoder) -> Unit {
  self.buffer = []
}

///|
fn find_crlf(buffer : Array[Byte], start : Int) -> Int? {
  if buffer.length() < 2 || start >= buffer.length() - 1 {
    return None
  }
  for index = start; index < buffer.length() - 1; index = index + 1 {
    if buffer[index] == 0x0d && buffer[index + 1] == 0x0a {
      return Some(index)
    }
  }
  None
}

///|
fn server_info_from_json(raw : String) -> Result[ServerInfo, NatsError] {
  let trimmed = raw.trim().to_owned()
  if !trimmed.has_prefix("{") || !trimmed.has_suffix("}") {
    return Err(
      nats_error(
        ProtocolViolation,
        "INFO",
        "INFO payload must be a JSON object",
      ),
    )
  }
  Ok(server_info(trimmed))
}

///|
fn parse_message_meta(
  tokens : Array[String],
  headers : Bool,
) -> Result[(String, Int, String?, Int, Int), NatsError] {
  let minimum = if headers { 5 } else { 4 }
  let maximum = minimum + 1
  if tokens.length() < minimum || tokens.length() > maximum {
    return Err(
      nats_error(
        InvalidCommand,
        "frame",
        "message frame has an invalid argument count",
      ),
    )
  }
  let subject = tokens[1]
  match validate_publish_subject(subject) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let sid = match parse_non_negative_int(tokens[2], "sid") {
    Ok(value) if value > 0 => value
    Ok(_) =>
      return Err(
        nats_error(InvalidSid, "sid", "subscription id must be positive"),
      )
    Err(error) => return Err(error)
  }
  if headers {
    let has_reply = tokens.length() == 6
    let reply = if has_reply { Some(tokens[3]) } else { None }
    let header_index = if has_reply { 4 } else { 3 }
    let total_index = header_index + 1
    match reply {
      Some(value) =>
        match validate_publish_subject(value) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      None => ()
    }
    let header_bytes = match
      parse_non_negative_int(tokens[header_index], "header_bytes") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let total_bytes = match
      parse_non_negative_int(tokens[total_index], "total_bytes") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if header_bytes > total_bytes {
      return Err(
        nats_error(
          ProtocolViolation,
          "header_bytes",
          "header length exceeds total length",
        ),
      )
    }
    Ok((subject, sid, reply, header_bytes, total_bytes))
  } else {
    let has_reply = tokens.length() == 5
    let reply = if has_reply { Some(tokens[3]) } else { None }
    let length_index = if has_reply { 4 } else { 3 }
    match reply {
      Some(value) =>
        match validate_publish_subject(value) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      None => ()
    }
    let payload_bytes = match
      parse_non_negative_int(tokens[length_index], "payload_bytes") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    Ok((subject, sid, reply, 0, payload_bytes))
  }
}

///|
fn parse_line_only(line : String) -> Result[ServerOp, NatsError] {
  if line == "PING" {
    return Ok(Ping)
  }
  if line == "PONG" {
    return Ok(Pong)
  }
  if line == "+OK" {
    return Ok(OkFrame)
  }
  if line.has_prefix("-ERR") {
    let detail = if line.length() > 4 {
      line[4:].to_owned().trim().to_owned()
    } else {
      ""
    }
    let cleaned = if detail.length() >= 2 &&
      detail.has_prefix("'") &&
      detail.has_suffix("'") {
      detail[1:detail.length() - 1].to_owned()
    } else {
      detail
    }
    return Ok(ServerError(cleaned))
  }
  if line.has_prefix("INFO ") {
    let info = match server_info_from_json(line[5:].to_owned()) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    return Ok(Info(info))
  }
  Err(nats_error(InvalidCommand, "frame", "unsupported server command"))
}

///|
fn verify_payload_terminator(
  buffer : Array[Byte],
  end : Int,
) -> Result[Unit, NatsError] {
  if end + 1 >= buffer.length() ||
    buffer[end] != 0x0d ||
    buffer[end + 1] != 0x0a {
    Err(
      nats_error(
        ProtocolViolation,
        "payload",
        "payload is not followed by CRLF",
      ),
    )
  } else {
    Ok(())
  }
}

///|
/// Appends a chunk and returns every complete operation now available.
pub fn ProtocolDecoder::push(
  self : ProtocolDecoder,
  chunk : Bytes,
) -> Result[Array[ServerOp], NatsError] {
  if self.buffer.length() + chunk.length() > self.limits.max_buffer {
    self.buffer = []
    return Err(
      nats_error(
        BufferLimitExceeded,
        "buffer",
        "decoder buffer exceeds configured limit",
      ),
    )
  }
  append_bytes(self.buffer, chunk)
  let output : Array[ServerOp] = []
  let mut consumed = 0
  while consumed < self.buffer.length() {
    let line_end = match find_crlf(self.buffer, consumed) {
      Some(value) => value
      None => {
        if self.buffer.length() - consumed > self.limits.max_control_line {
          self.buffer = []
          return Err(
            nats_error(
              FrameTooLarge,
              "control_line",
              "control line exceeds configured limit",
            ),
          )
        }
        break
      }
    }
    if line_end - consumed > self.limits.max_control_line {
      self.buffer = []
      return Err(
        nats_error(
          FrameTooLarge,
          "control_line",
          "control line exceeds configured limit",
        ),
      )
    }
    let line = text_from_bytes(
      array_slice_bytes(self.buffer, consumed, line_end),
    )
    let tokens = control_tokens(line)
    if tokens.length() == 0 {
      self.buffer = []
      return Err(nats_error(InvalidCommand, "frame", "empty server command"))
    }
    if tokens[0] == "MSG" || tokens[0] == "HMSG" {
      let has_headers = tokens[0] == "HMSG"
      let meta = match parse_message_meta(tokens, has_headers) {
        Ok(value) => value
        Err(error) => {
          self.buffer = []
          return Err(error)
        }
      }
      if meta.4 > self.limits.max_payload {
        self.buffer = []
        return Err(
          nats_error(
            PayloadTooLarge,
            "payload",
            "server payload exceeds configured limit",
          ),
        )
      }
      if meta.3 > self.limits.max_headers {
        self.buffer = []
        return Err(
          nats_error(
            FrameTooLarge,
            "headers",
            "server header block exceeds configured limit",
          ),
        )
      }
      let payload_start = line_end + 2
      let payload_end = payload_start + meta.4
      if payload_end + 2 > self.buffer.length() {
        break
      }
      match verify_payload_terminator(self.buffer, payload_end) {
        Ok(_) => ()
        Err(error) => {
          self.buffer = []
          return Err(error)
        }
      }
      let headers = if has_headers {
        let raw = array_slice_bytes(
          self.buffer,
          payload_start,
          payload_start + meta.3,
        )
        match decode_headers(raw, limits=self.limits) {
          Ok(value) => Some(value)
          Err(error) => {
            self.buffer = []
            return Err(error)
          }
        }
      } else {
        None
      }
      let body = array_slice_bytes(
        self.buffer,
        payload_start + meta.3,
        payload_end,
      )
      output.push(
        Message(nats_message(meta.0, meta.1, body, reply_to=meta.2, headers~)),
      )
      consumed = payload_end + 2
    } else {
      let operation = match parse_line_only(line) {
        Ok(value) => value
        Err(error) => {
          self.buffer = []
          return Err(error)
        }
      }
      output.push(operation)
      consumed = line_end + 2
    }
  }
  if consumed > 0 {
    self.buffer = self.buffer[consumed:].to_owned()
  }
  Ok(output)
}
