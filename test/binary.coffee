runner.mettle ->
  @tell 'int'
  min = - Math.pow(2, 31)
  max =   Math.pow(2, 31) - 1
  rnd =   Math.floor(Math.random() * (max - min)) + min
  assert.equal Buffer.fromInt(min).toInt(), min
  assert.equal Buffer.fromInt(max).toInt(), max
  assert.equal Buffer.fromInt(rnd).toInt(), rnd
  @tell 'float'
  assert.equal Buffer.fromFloat(12345.12345).toFloat(), 12345.12345
  for i in [1..50]
    v = Math.pow(Math.random(), 64)
    assert.equal Buffer.fromFloat(v).toFloat(), v
  @tell 'date'
  date = new Date 1291018862848
  assert.equal Buffer.fromDate(date).toDate().getTime(), date.getTime()
  date = new Date
  assert.equal Buffer.fromDate(date).toDate().getTime(), date.getTime()
  @next()