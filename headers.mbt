///|
pub struct HeaderEntry {
  name : String
  value : String
} derive(Debug, Eq)

///|
pub fn HeaderEntry::name(self : HeaderEntry) -> String {
  self.name
}

///|
pub fn HeaderEntry::value(self : HeaderEntry) -> String {
  self.value
}

///|
/// NATS/1.0 header block. Repeated field names are preserved in insertion
/// order because message metadata such as `Nats-Msg-Id` may be inspected or
/// forwarded without lossy normalization.
pub struct NatsHeaders {
  status_code : Int?
  status_text : String?
  entries : Array[HeaderEntry]
} derive(Debug, Eq)

///|
pub fn nats_headers(
  status_code? : Int? = None,
  status_text? : String? = None,
) -> NatsHeaders {
  { status_code, status_text, entries: [] }
}

///|
pub fn NatsHeaders::status_code(self : NatsHeaders) -> Int? {
  self.status_code
}

///|
pub fn NatsHeaders::status_text(self : NatsHeaders) -> String? {
  self.status_text
}

///|
pub fn NatsHeaders::entries(self : NatsHeaders) -> Array[HeaderEntry] {
  self.entries.copy()
}

///|
pub fn NatsHeaders::values(self : NatsHeaders, name : String) -> Array[String] {
  let output : Array[String] = []
  let lowered = name.to_lower()
  for entry in self.entries {
    if entry.name.to_lower() == lowered {
      output.push(entry.value)
    }
  }
  output
}

///|
pub fn NatsHeaders::first(self : NatsHeaders, name : String) -> String? {
  let lowered = name.to_lower()
  for entry in self.entries {
    if entry.name.to_lower() == lowered {
      return Some(entry.value)
    }
  }
  None
}

///|
fn validate_header_name(name : String) -> Result[Unit, NatsError] {
  if name.is_empty() {
    return Err(
      nats_error(InvalidHeader, "name", "header name must not be empty"),
    )
  }
  if has_cr_or_lf(name) || name.contains(":") {
    return Err(
      nats_error(
        InvalidHeader,
        "name",
        "header name contains a reserved character",
      ),
    )
  }
  for char in name.to_array() {
    if char == ' ' || char == '\t' {
      return Err(
        nats_error(
          InvalidHeader,
          "name",
          "header name must not contain whitespace",
        ),
      )
    }
  }
  Ok(())
}

///|
pub fn NatsHeaders::append(
  self : NatsHeaders,
  name : String,
  value : String,
) -> Result[NatsHeaders, NatsError] {
  match validate_header_name(name) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if has_cr_or_lf(value) {
    return Err(
      nats_error(
        InvalidHeader,
        "value",
        "header value must not contain CR or LF",
      ),
    )
  }
  let entries = self.entries.copy()
  entries.push({ name, value })
  Ok({ status_code: self.status_code, status_text: self.status_text, entries })
}

///|
fn validate_header_status(headers : NatsHeaders) -> Result[Unit, NatsError] {
  match headers.status_code {
    None =>
      if headers.status_text is Some(_) {
        Err(
          nats_error(
            InvalidHeader,
            "status",
            "status text requires a status code",
          ),
        )
      } else {
        Ok(())
      }
    Some(code) =>
      if code < 100 || code > 999 {
        Err(
          nats_error(
            InvalidHeader,
            "status",
            "status code must contain three digits",
          ),
        )
      } else {
        match headers.status_text {
          Some(text) if has_cr_or_lf(text) =>
            Err(
              nats_error(
                InvalidHeader,
                "status",
                "status text must not contain CR or LF",
              ),
            )
          _ => Ok(())
        }
      }
  }
}

///|
/// Serializes the complete header section, including the required blank line.
pub fn encode_headers(headers : NatsHeaders) -> Result[Bytes, NatsError] {
  match validate_header_status(headers) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let output = StringBuilder()
  output.write_string("NATS/1.0")
  match headers.status_code {
    Some(code) => {
      output.write_char(' ')
      output.write_string(code.to_string())
      match headers.status_text {
        Some(text) if !text.is_empty() => {
          output.write_char(' ')
          output.write_string(text)
        }
        _ => ()
      }
    }
    None => ()
  }
  output.write_string("\r\n")
  for entry in headers.entries {
    match validate_header_name(entry.name) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    if has_cr_or_lf(entry.value) {
      return Err(
        nats_error(
          InvalidHeader,
          "value",
          "header value must not contain CR or LF",
        ),
      )
    }
    output.write_string(entry.name)
    output.write_string(": ")
    output.write_string(entry.value)
    output.write_string("\r\n")
  }
  output.write_string("\r\n")
  Ok(bytes_from_text(output.to_string()))
}

///|
fn split_header_lines(value : String) -> Array[String] {
  value.split("\r\n").map(part => part.to_owned()).to_array()
}

///|
fn split_header_entry(line : String) -> Result[(String, String), NatsError] {
  let chars = line.to_array()
  let mut separator = -1
  for index = 0; index < chars.length(); index = index + 1 {
    if chars[index] == ':' {
      separator = index
      break
    }
  }
  if separator <= 0 {
    return Err(
      nats_error(
        InvalidHeader,
        "line",
        "header line must contain a field name and colon",
      ),
    )
  }
  let name = line[:separator].to_owned()
  let mut start = separator + 1
  while start < chars.length() && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  Ok((name, line[start:].to_owned()))
}

///|
/// Parses one complete NATS/1.0 header section.
pub fn decode_headers(
  value : Bytes,
  limits? : NatsLimits = nats_limits(),
) -> Result[NatsHeaders, NatsError] {
  if value.length() > limits.max_headers {
    return Err(
      nats_error(
        FrameTooLarge,
        "headers",
        "header section exceeds configured limit",
      ),
    )
  }
  let text = text_from_bytes(value)
  if !text.has_suffix("\r\n\r\n") {
    return Err(
      nats_error(
        InvalidHeader,
        "headers",
        "header section must end with a blank line",
      ),
    )
  }
  let lines = split_header_lines(text)
  if lines.length() < 3 {
    return Err(
      nats_error(InvalidHeader, "headers", "header section is incomplete"),
    )
  }
  let first = control_tokens(lines[0])
  if first.length() < 1 || first[0] != "NATS/1.0" {
    return Err(
      nats_error(
        InvalidHeader,
        "preamble",
        "header block must start with NATS/1.0",
      ),
    )
  }
  let mut headers = nats_headers()
  if first.length() >= 2 {
    let code = match parse_non_negative_int(first[1], "status") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let status_text = if first.length() >= 3 {
      let builder = StringBuilder()
      for index = 2; index < first.length(); index = index + 1 {
        if index > 2 {
          builder.write_char(' ')
        }
        builder.write_string(first[index])
      }
      Some(builder.to_string())
    } else {
      None
    }
    headers = nats_headers(status_code=Some(code), status_text~)
  }
  for index = 1; index < lines.length() - 2; index = index + 1 {
    if lines[index].is_empty() {
      return Err(
        nats_error(InvalidHeader, "headers", "unexpected blank header line"),
      )
    }
    let entry = match split_header_entry(lines[index]) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    headers = match headers.append(entry.0, entry.1) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  match validate_header_status(headers) {
    Ok(_) => Ok(headers)
    Err(error) => Err(error)
  }
}
