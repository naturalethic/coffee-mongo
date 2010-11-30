runner.mettle ->
  _ = bson._private
  @tell 'buffer_to_hex'
  assert.equal _.buffer_to_hex(new Buffer [0, 1, 2, 3, 4, 5, 6, 7]), '0001020304050607'
  assert.equal _.buffer_to_hex(new Buffer [8, 9, 10, 11, 12, 13, 14, 15]), '08090a0b0c0d0e0f'
  @tell 'reverse_buffer'
  assert.equal _.buffer_to_hex(_.reverse_buffer(new Buffer [0, 1, 2, 3])), '03020100'
  @tell 'int32'
  min = - Math.pow(2, 31)
  max =   Math.pow(2, 31) - 1
  rnd =   Math.floor(Math.random() * (max - min)) + min
  assert.equal _.buffer_to_int32(_.int32_to_buffer min), min
  assert.equal _.buffer_to_int32(_.int32_to_buffer max), max
  assert.equal _.buffer_to_int32(_.int32_to_buffer rnd), rnd
  assert.equal _.buffer_to_hex(_.int32_to_buffer 219094091), '4b1c0f0d'
  assert.equal _.buffer_to_hex(_.int32_to_buffer -2138948569), '273c8280'
  @tell 'int64'
  min = - Math.pow(2, 53)
  max =   Math.pow(2, 53)
  rnd =   Math.floor(Math.random() * (max - min)) + min
  assert.equal _.buffer_to_int64(_.int64_to_buffer min), min
  assert.equal _.buffer_to_int64(_.int64_to_buffer max), max
  assert.equal _.buffer_to_int64(_.int64_to_buffer rnd), rnd
  assert.equal _.buffer_to_hex(_.int64_to_buffer -2251881397092352), '80080012fec00000'
  assert.equal _.buffer_to_hex(_.int64_to_buffer 2105347084910592), '00077acd51200000'
  assert.equal _.buffer_to_hex(_.int64_to_buffer 8466520598380544), '001e144170c00000'
  @tell 'float'
  # XXX: check actual bytes for some specific values to ensure correct IEEE 754 coding
  assert.equal _.buffer_to_float(_.float_to_buffer 12345.12345), 12345.12345
  for i in [1..50]
    v = Math.pow(Math.random(), 64)
    assert.equal _.buffer_to_float(_.float_to_buffer v), v
  @tell 'BSONBoolean'
  v = new _.BSONBoolean true
  assert.equal v.toHex(), '01'
  assert.equal v.value(), true
  v = new _.BSONBoolean false
  assert.equal v.toHex(), '00'
  assert.equal v.value(), false
  @tell 'BSONFloat'
  v = new _.BSONFloat 12345.54321
  assert.equal v.toHex(), '6ec0e787c51cc840'
  assert.equal v.value(), 12345.54321
  v = new _.BSONFloat 1995
  assert.equal v.value(), 1995
  @tell 'BSONInt32'
  v = new _.BSONInt32 218584581
  assert.equal v.toHex(), '0556070d'
  assert.equal v.value(), 218584581
  @tell 'BSONInt64'
  v = new _.BSONInt64 8277520598380522
  assert.equal v.toHex(), '001d685c72e32fea'
  assert.equal v.value(), 8277520598380522
  @tell 'BSONKey'
  v = new _.BSONKey 'name'
  assert.equal v.toHex(), '6e616d6500'
  assert.equal v.value(), 'name'
  @tell 'BSONString'
  v = new _.BSONString 'hello'
  assert.equal v.toHex(), '0600000068656c6c6f00'
  assert.equal v.value(), 'hello'
  @tell 'BSONObjectID'
  v = new _.BSONObjectID()
  assert.equal v.length, 12
  h = '1234567890ab1234567890ab'
  assert.equal new _.BSONObjectID(h).toHex(), h
  @tell 'BSONDate'
  d = new Date 1291100178549
  v = new _.BSONDate d
  assert.equal v.toHex(), '0000012c9b914875'
  assert.equal v.value().getTime(), d.getTime()
  @tell 'BSONNull'
  v = new _.BSONNull(new _.BSONNull)
  assert.equal v.toHex(), ''
  assert.equal v.value(), null
  @tell 'BSONElement'
  e = new _.BSONElement 'really?', true
  assert.equal e.type, 0x08
  assert.equal e.key(), 'really?'
  assert.equal e.value(), true
  e = new _.BSONElement 'bargain', 19.95
  assert.equal e.type, 0x01
  assert.equal e.value(), 19.95
  e = new _.BSONElement 'party', 1999
  assert.equal e.type, 0x01
  assert.equal e.value(), 1999
  e = new _.BSONElement 'no way!', 'waaaay!'
  assert.equal e.type, 0x02
  assert.equal e.value(), 'waaaay!'
  d = new Date(Date.parse 'July 4, 1776')
  e = new _.BSONElement 'revolution', d
  assert.equal e.type, 0x09
  assert.equal e.value().getTime(), d.getTime()
  @tell 'BSONDocument'
  obj = { i: 404, f: 1.05, b: true, d: d }
  assert.deepEqual (new _.BSONDocument(new _.BSONDocument obj)).value(), obj
  obj = { d: { x: 1 } }
  assert.deepEqual (new _.BSONDocument(new _.BSONDocument obj)).value(), obj
  obj = { d: { x: 1, deep: { foo: 'bar' } } }
  assert.deepEqual (new _.BSONDocument(new _.BSONDocument obj)).value(), obj
  obj = { arr: [ 1, 2, 3 ] }
  assert.deepEqual (new _.BSONDocument(new _.BSONDocument obj)).value(), obj
  obj = { arr: [ 1, 2, 3, 'foo', 'bar', 5.8, obj: { x: 1, date: new Date } ] }
  assert.deepEqual (new _.BSONDocument(new _.BSONDocument obj)).value(), obj
  assert.deepEqual bson.deserialize(bson.serialize(obj)), obj
  @next()

