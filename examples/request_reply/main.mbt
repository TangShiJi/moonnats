///|
fn main {
  let client = @moonnats.client_core()
  client.begin_connection().unwrap()
  ignore(client.receive(b"INFO {}\r\n").unwrap())
  let request = client.request("math.add", b"40,2", 100, 30).unwrap()
  println("reply inbox=" + request.inbox())
  for frame in client.drain_outbox() {
    println(@utf8.decode_lossy(frame[:]).trim().to_owned())
  }
  let wire = "MSG " +
    request.inbox() +
    " " +
    request.sid().to_string() +
    " 2\r\n42\r\n"
  let events = client.receive(@utf8.encode(wire[:])).unwrap()
  match events[0] {
    Delivered(delivery) =>
      println("response=" + @utf8.decode_lossy(delivery.message().payload()[:]))
    _ => println("unexpected event")
  }
}
