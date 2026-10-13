///|
fn contains_subject_whitespace(value : String) -> Bool {
  for char in value.to_array() {
    if char == ' ' || char == '\t' || char == '\r' || char == '\n' {
      return true
    }
  }
  false
}

///|
fn subject_tokens(value : String) -> Array[String] {
  value.split(".").map(item => item.to_owned()).to_array()
}

///|
/// Validates a concrete publish subject. Wildcards are deliberately rejected.
pub fn validate_publish_subject(subject : String) -> Result[Unit, NatsError] {
  if subject.is_empty() {
    return Err(
      nats_error(InvalidSubject, "subject", "subject must not be empty"),
    )
  }
  if contains_subject_whitespace(subject) {
    return Err(
      nats_error(
        InvalidSubject,
        "subject",
        "subject must not contain whitespace",
      ),
    )
  }
  let tokens = subject_tokens(subject)
  for token in tokens {
    if token.is_empty() {
      return Err(
        nats_error(
          InvalidSubject,
          "subject",
          "subject tokens must not be empty",
        ),
      )
    }
    if token.contains("*") || token.contains(">") {
      return Err(
        nats_error(
          InvalidSubject,
          "subject",
          "publish subject must not contain wildcards",
        ),
      )
    }
  }
  Ok(())
}

///|
/// Validates a subscription subject. `*` matches one token and `>` may only
/// occur as the final token, matching one or more remaining tokens.
pub fn validate_subscription_subject(
  subject : String,
) -> Result[Unit, NatsError] {
  if subject.is_empty() {
    return Err(
      nats_error(InvalidSubject, "subject", "subject must not be empty"),
    )
  }
  if contains_subject_whitespace(subject) {
    return Err(
      nats_error(
        InvalidSubject,
        "subject",
        "subject must not contain whitespace",
      ),
    )
  }
  let tokens = subject_tokens(subject)
  for index = 0; index < tokens.length(); index = index + 1 {
    let token = tokens[index]
    if token.is_empty() {
      return Err(
        nats_error(
          InvalidSubject,
          "subject",
          "subject tokens must not be empty",
        ),
      )
    }
    if token.contains("*") && token != "*" {
      return Err(
        nats_error(InvalidSubject, "subject", "* must occupy a complete token"),
      )
    }
    if token.contains(">") && (token != ">" || index != tokens.length() - 1) {
      return Err(
        nats_error(
          InvalidSubject,
          "subject",
          "> must be the final complete token",
        ),
      )
    }
  }
  Ok(())
}

///|
pub fn validate_queue_group(queue : String) -> Result[Unit, NatsError] {
  if queue.is_empty() {
    return Err(
      nats_error(InvalidQueueGroup, "queue", "queue group must not be empty"),
    )
  }
  if contains_subject_whitespace(queue) ||
    queue.contains("*") ||
    queue.contains(">") {
    return Err(
      nats_error(
        InvalidQueueGroup,
        "queue",
        "queue group contains a reserved character",
      ),
    )
  }
  Ok(())
}

///|
/// Applies NATS token wildcard semantics after validating both operands.
pub fn subject_matches(
  pattern : String,
  subject : String,
) -> Result[Bool, NatsError] {
  match validate_subscription_subject(pattern) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match validate_publish_subject(subject) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let expected = subject_tokens(pattern)
  let actual = subject_tokens(subject)
  let mut index = 0
  while index < expected.length() {
    if expected[index] == ">" {
      return Ok(index < actual.length())
    }
    if index >= actual.length() {
      return Ok(false)
    }
    if expected[index] != "*" && expected[index] != actual[index] {
      return Ok(false)
    }
    index = index + 1
  }
  Ok(index == actual.length())
}

///|
pub fn inbox_subject(
  prefix : String,
  sequence : Int,
) -> Result[String, NatsError] {
  match validate_publish_subject(prefix) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if sequence < 0 {
    return Err(
      nats_error(
        InvalidInteger,
        "sequence",
        "inbox sequence must not be negative",
      ),
    )
  }
  Ok(prefix + "." + sequence.to_string())
}
