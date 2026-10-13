///|
fn main {
  let decoder = @moonnats.protocol_decoder(
    limits=@moonnats.nats_limits(max_buffer=64),
  )
  let mut decoded = 0
  for _index = 0; _index < 100000; _index = _index + 1 {
    decoded = decoded + decoder.push(b"PING\r\n").unwrap().length()
  }
  println(decoded)
}
