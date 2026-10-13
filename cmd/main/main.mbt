///|
/// Minimal protocol smoke command used by release verification.
fn main {
  let frame = @moonnats.encode_publish("demo.events", b"hello").unwrap()
  println(@utf8.decode_lossy(frame[:]).trim().to_owned())
}
