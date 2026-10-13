///|
fn main {
  let client = @moonnats.client_core()
  client.begin_connection().unwrap()
  ignore(client.receive(b"INFO {\"headers\":true}\r\n").unwrap())
  let sid = client.subscribe("orders.*").unwrap()
  println("subscription sid=" + sid.to_string())
  ignore(client.drain_outbox())
  let events = client
    .receive(b"MSG orders.created 1 8\r\norder-42\r\n")
    .unwrap()
  match events[0] {
    Delivered(delivery) =>
      println(
        delivery.message().subject() +
        " => " +
        @utf8.decode_lossy(delivery.message().payload()[:]),
      )
    _ => println("unexpected event")
  }
}
