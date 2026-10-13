///|
/// Stable error categories let downstream adapters map failures without
/// parsing human-readable messages.
pub(all) enum NatsErrorKind {
  InvalidSubject
  InvalidQueueGroup
  InvalidSid
  InvalidHeader
  InvalidCommand
  InvalidInteger
  FrameTooLarge
  PayloadTooLarge
  BufferLimitExceeded
  ProtocolViolation
  InvalidState
  DuplicateSubscription
  UnknownSubscription
  OutboxFull
  RequestLimitExceeded
  NoServer
} derive(Debug, Eq)

///|
/// Structured error returned by all validation, codec, and client APIs.
pub struct NatsError {
  kind : NatsErrorKind
  field : String
  message : String
} derive(Debug, Eq)

///|
pub fn NatsError::kind(self : NatsError) -> NatsErrorKind {
  self.kind
}

///|
pub fn NatsError::field(self : NatsError) -> String {
  self.field
}

///|
pub fn NatsError::message(self : NatsError) -> String {
  self.message
}

///|
fn nats_error(
  kind : NatsErrorKind,
  field : String,
  message : String,
) -> NatsError {
  { kind, field, message }
}
