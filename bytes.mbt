///|
fn bytes_from_text(value : String) -> Bytes {
  @utf8.encode(value[:])
}

///|
fn text_from_bytes(value : Bytes) -> String {
  @utf8.decode_lossy(value[:])
}

///|
fn append_text(output : Array[Byte], value : String) -> Unit {
  for byte in @utf8.encode(value[:]) {
    output.push(byte)
  }
}

///|
fn append_bytes(output : Array[Byte], value : Bytes) -> Unit {
  for byte in value {
    output.push(byte)
  }
}

///|
fn bytes_concat(parts : Array[Bytes]) -> Bytes {
  let output : Array[Byte] = []
  for part in parts {
    append_bytes(output, part)
  }
  Bytes::from_array(output[:])
}

///|
fn bytes_slice(value : Bytes, start : Int, end : Int) -> Bytes {
  value[start:end].to_owned()
}

///|
fn array_slice_bytes(value : Array[Byte], start : Int, end : Int) -> Bytes {
  Bytes::from_array(value[start:end])
}

///|
fn parse_non_negative_int(
  value : String,
  field : String,
) -> Result[Int, NatsError] {
  if value.is_empty() {
    return Err(nats_error(InvalidInteger, field, "integer must not be empty"))
  }
  let mut result = 0
  for char in value.to_array() {
    if char < '0' || char > '9' {
      return Err(
        nats_error(InvalidInteger, field, "integer contains a non-digit"),
      )
    }
    let digit = char.to_int() - '0'.to_int()
    if result > (@int.MAX_VALUE - digit) / 10 {
      return Err(nats_error(InvalidInteger, field, "integer overflows"))
    }
    result = result * 10 + digit
  }
  Ok(result)
}

///|
fn control_tokens(line : String) -> Array[String] {
  let output : Array[String] = []
  for part in line.split(" ") {
    let token = part.to_owned()
    if !token.is_empty() {
      output.push(token)
    }
  }
  output
}

///|
fn has_cr_or_lf(value : String) -> Bool {
  value.contains("\r") || value.contains("\n")
}
