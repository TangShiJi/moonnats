///|
fn next_seed(value : Int) -> Int {
  (value * 1103515245 + 12345) & 0x7fffffff
}

///|
test "deterministic chunk fuzz never loses or duplicates frames" {
  let source = b"PING\r\nPONG\r\n+OK\r\nMSG events 1 3\r\none\r\nPING\r\n"
  for initial_seed = 1; initial_seed <= 64; initial_seed = initial_seed + 1 {
    let decoder = protocol_decoder()
    let operations : Array[ServerOp] = []
    let mut offset = 0
    let mut seed = initial_seed
    while offset < source.length() {
      seed = next_seed(seed)
      let chunk_size = seed % 7 + 1
      let end = if offset + chunk_size < source.length() {
        offset + chunk_size
      } else {
        source.length()
      }
      let decoded = decoder.push(source[offset:end].to_owned()).unwrap()
      for operation in decoded {
        operations.push(operation)
      }
      offset = end
    }
    assert_eq(operations.length(), 5)
    assert_true(operations[0] is Ping)
    assert_true(operations[1] is Pong)
    assert_true(operations[2] is OkFrame)
    assert_true(operations[3] is Message(_))
    assert_true(operations[4] is Ping)
    assert_eq(decoder.buffered_bytes(), 0)
  }
}

///|
test "bounded random garbage either waits within limit or errors" {
  let limits = nats_limits(max_control_line=32, max_buffer=64)
  for initial_seed = 1; initial_seed <= 128; initial_seed = initial_seed + 1 {
    let bytes : Array[Byte] = []
    let mut seed = initial_seed
    let length = initial_seed % 40
    for _index = 0; _index < length; _index = _index + 1 {
      seed = next_seed(seed)
      bytes.push((seed % 256).to_byte())
    }
    let decoder = protocol_decoder(limits~)
    match decoder.push(Bytes::from_array(bytes[:])) {
      Ok(_) => assert_true(decoder.buffered_bytes() <= 32)
      Err(_) => assert_eq(decoder.buffered_bytes(), 0)
    }
  }
}
