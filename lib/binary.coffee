int_min   = - Math.pow(2, 31)
int_max   =   Math.pow(2, 31) - 1
int_top   =   Math.pow 2, 32

Buffer.fromInt = (value) ->
  value = int_min if value < int_min
  value = int_max if value > int_max
  buffer = new Buffer 4
  for i in [0..3]
    buffer[i] = value & 0xff
    value >>= 8
  buffer

Buffer::toInt = ->
  value = 0
  f = 1
  for i in [0..3]
    value += @[i] * f
    f *= 256
  if value & int_min
    value -= int_top
  value

Buffer.fromFloat = (value) ->
  mLen  = 52
  eLen  = 11
  eMax  = (1 << eLen) - 1
  eBias = eMax >> 1
  s     = if value < 0 then 1 else 0
  value = Math.abs value
  if isNaN value or value == Infinity
    m = if isNaN value then 1 else 0
    e = eMax
  else
    e = Math.floor Math.log(value) / Math.LN2
    if value * (c = Math.pow(2, -e)) < 1
      e--
      c *= 2
    if value * c >= 2
      e++
      c /= 2
    if e + eBias >= eMax
      m = 0
      e = eMax
    else if e + eBias >= 1
      m = (value * c - 1) * Math.pow 2, mLen
      e = e + eBias
    else
      m = value * Math.pow(2, eBias - 1) * Math.pow(2, mLen)
      e = 0
  buffer = new Buffer 8
  i = 0
  while mLen >= 8
    buffer[i++] = m & 0xff
    m /= 256
    mLen -= 8
  e = (e << mLen) | m
  eLen += mLen
  while eLen > 0
    buffer[i++] = e & 0xff
    e /= 256
    eLen -= 8
  buffer[i - 1] |= s * 128
  buffer

Buffer::toFloat = ->
  mLen  = 52
  eLen  = 11
  eMax  = (1 << eLen) - 1
  eBias = eMax >> 1
  nBits = -7
  i     = 7
  s     = @[i--]
  e     = s & ((1 << (-nBits)) - 1)
  s    >>= (-nBits)
  nBits += eLen
  while nBits > 0
    e = e * 256 + @[i--]
    nBits -= 8
  m = e & ((1 << (-nBits)) - 1)
  e >>= (-nBits)
  nBits += mLen
  while nBits > 0
    m = m * 256 + @[i--]
    nBits -= 8
  switch e
    when 0
      e = 1 - eBias
    when eMax
      return if m then NaN else ((if s then -1 else 1) * Infinity)
    else
      m += Math.pow 2, mLen
      e -= eBias
  (if s then -1 else 1) * m * Math.pow 2, e - mLen

Buffer::toDate = ->
  new Date(parseInt(@toHex(), 16))

Buffer.fromDate = (value) ->
  s = value.getTime().toString(16)
  while s.length < 16
    s = '0' + s
  Buffer.fromHex s

Buffer.fromHex = (s) ->
  s = '0' + s if s.length % 2 != 0
  buffer = new Buffer s.length / 2
  for i in [0...s.length]
    buffer[i/2] = parseInt(s.substr(i, 2), 16)
  buffer

Buffer::toHex = ->
  ((if @[i] < 16 then '0' else '') + @[i].toString 16 for i in [0...@length]).join('')

Buffer::toArray = ->
  @[i] for i in [0...@length]

Buffer::reverse = ->
  target = new Buffer @length
  for i in [0...@length]
    @.copy target, @length - i - 1, i, i + 1
  target.copy @, 0, 0
  @

