///|
fn main {
  let first = @moonnats.encode_subscribe(
    "jobs.resize",
    1,
    queue=Some("image-workers"),
  ).unwrap()
  let second = @moonnats.encode_subscribe(
    "jobs.resize",
    2,
    queue=Some("image-workers"),
  ).unwrap()
  println(@utf8.decode_lossy(first[:]).trim().to_owned())
  println(@utf8.decode_lossy(second[:]).trim().to_owned())
  println("the NATS server chooses one member of the queue group")
}
