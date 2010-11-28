# buffer.coffee
#
# Binary and other addons for buffer
#
# Reference:
# http://jsfromhell.com/classes/binary-parser
#
# Buffers default to little-endian -- use Buffer.reverse to make big-endian

global.util   = require 'util'
global.put    = (args...) -> util.print a for a in args
global.puts   = (args...) -> put a + '\n' for a in args
global.p      = (args...) -> puts util.inspect a, true, null for a in args

shl = (a, b) ->
  while b--
    if ( ( a %= 0x7fffffff + 1 ) & 0x40000000 ) == 0x40000000
      a *= 2
    else
      a = ( a - 0x40000000 ) * 2 + 0x7fffffff + 1
  a

sumBytes = (buffer, start, length) ->
  return 0 if start < 0 or length <= 0
  bytes_needed = (start + length)
  if buffer.length < bytes_needed
    throw Error "binary shortfall: buffer size: #{buffer.length}, size needed: #{bytes_needed}"
  sum = buffer[start]
  n = 1
  for i in [(start + 1)..(start + length - 1)]
    sum += buffer[i] * (Math.pow(2, (n++ * 8)))
  sum

# XXX: This didn't work with longs greater than maxint, suspicious of it's efficacy with doubles
sumBits = (buffer, start, length) ->
  return 0 if start < 0 or length <= 0
  bytes_needed = -( -(start + length) >> 3 )
  if buffer.length < bytes_needed
    throw Error "binary shortfall: buffer size: #{buffer.length}, size needed: #{bytes_needed}"
  offset_left  = ( start + length ) % 8
  offset_right = start % 8
  current      = buffer.length - ( start >> 3 ) - 1
  last         = buffer.length + ( -( start + length ) >> 3 )
  diff         = current - last
  sum          = ( ( buffer[ buffer.length - current - 1 ] >> offset_right ) & ( ( 1 << ( if diff then 8 - offset_right else length ) ) - 1 ) ) +
                 ( diff && if offset_left then ( buffer[ buffer.length - last++ - 1] & ( ( 1 << offset_left ) - 1 ) ) << ( diff-- << 3 ) - offset_right else 0 )
  while diff
    sum += shl buffer[ buffer.length - last++ - 1], ( diff-- << 3 ) - offset_right
  sum

decodeInt = (buffer, bits, signed) ->
  bits   ?= 32
  signed ?= true
  if bits % 8 == 0
    value = sumBytes buffer, 0, bits / 8
  else
    value = sumBits buffer, 0, bits
  max = Math.pow 2, bits
  if signed and value >= max / 2
    return value - max
  value

encodeInt = (value, bits, signed) ->
  bits   ?= 32
  signed ?= true
  # XXX: Hmm this should check signed
  max     = Math.pow 2, bits
  min     = -( max / 2 )
  if not ( min <= value <= max )
    throw Error "binary overflow: #{value} won't fit #{bits} bits"
  value += max if value < 0
  bytes = []
  while value
    bytes.push value % 256
    value = Math.floor value / 256
  bits = -( -bits >> 3 ) - bytes.length
  while bits--
    bytes.push 0
  new Buffer bytes

decodeFloat = (buffer, precision_bits, exponent_bits) ->
  bytes_needed = -( -(precision_bits + exponent_bits + 1 ) >> 3 )
  if buffer.length < bytes_needed
    throw Error "binary shortfall: buffer size: #{buffer.length}, size needed: #{bytes_needed}"
  bias        = Math.pow( 2, exponent_bits - 1 ) - 1
  signal      = sumBits buffer, precision_bits + exponent_bits, 1
  exponent    = sumBits buffer, precision_bits, exponent_bits
  significand = 0
  divisor     = 2
  current     = buffer.length + ( -precision_bits >> 3 ) - 1
  while precision_bits
    byte  = buffer[ buffer.length - ++current - 1 ]
    start = precision_bits % 8 or 8
    mask  = 1 << start
    while mask >>= 1
      ( byte & mask ) and ( significand += 1 / divisor )
      divisor *= 2
    precision_bits -= start
  if exponent == ( bias << 1 ) + 1
    if significand
      NaN
    else
      if signal
        -Infinity
      else
        +Infinity
  else
    if exponent or significand
      if not exponent
        v = Math.pow( 2, -bias + 1 ) * significand
      else
        v = Math.pow( 2, exponent - bias ) * ( 1 + significand )
    else
      0
    ( 1 + signal * -2 ) * v

# XXX: This is a (mostly) straight ignorant port and really needs to be refactored.
encodeFloat = (value, precision_bits, exponent_bits) ->
  bias           = Math.pow( 2, exponent_bits - 1 ) - 1
  min_exp        = -bias + 1
  max_exp        = bias
  min_unnorm_exp = min_exp - precision_bits
  status         = 0
  n              = parseFloat( value )
  status         = n if isNaN( n ) or n == -Infinity or n == +Infinity
  exp            = 0
  len            = 2 * bias + 1 + precision_bits + 3
  bin            = new Array len
  signal         = ( n = if status != 0 then 0 else n ) < 0
  abs            = Math.abs value
  int_part       = Math.floor abs
  float_part     = abs - int_part
  i              = len
  j              = null
  while i
    bin[ --i ] = 0
  i = bias + 2
  while int_part and i
    bin[ --i ] = int_part % 2
    int_part = Math.floor int_part / 2
  i = bias + 1
  while float_part > 0 and i
    ( bin[ ++i ] = ( ( float_part *= 2 ) >= 1 ) - 0 ) and --float_part
  i = 0
  while i < len and not bin[i]
    i++
  exp = bias + 1 - i
  if exp >= min_exp and exp <= max_exp
    i += 1
  else
    exp = min_exp - 1
    i = bias + 1 + exp
  last = precision_bits - 1 + i
  if bin[ last + 1 ]
    rounded = bin[ last ]
    if not rounded
      j = last + 2
      while not rounded and j < len
        rounded = bin[ j++ ]
    j = last + 1
    while rounded and --j >= 0
      bin[ j ] = not bin[ j ] - 0 and rounded = 0
  if i - 2 < 0
    i = 0
  else
    i = -2
  while i < len and not bin[ i ]
    i++
  exp = bias + 1 - i
  if exp >= min_exp and exp <= max_exp
    i++
  else if exp < min_exp
    if exp != bias + 1 - len and exp < min_unnorm_exp
      throw Error 'binary underflow decoding float'
    exp = min_exp - 1
    i = bias + 1 - exp
  if int_part or status != 0
    throw Error 'binary overflow decoding float'
  n = Math.abs exp + bias
  j = exponent_bits + 1
  result = ''
  while --j
    result = ( n % 2 ) + result
    n = n >>= 1
  result = (if signal then '1' else '0') + result + bin.slice( i, i + precision_bits ).join('')
  buffer = Buffer result.length / 8
  for i in [0...buffer.length]
    buffer[buffer.length - i - 1] = parseInt result.substr(i * 8, 8), 2
  buffer

Buffer.prototype.toByte   =     -> decodeInt   @, 8,  false
Buffer.fromByte           = (n) -> encodeInt   n, 8,  false
Buffer.prototype.toShort  =     -> decodeInt   @, 16, true
Buffer.fromShort          = (n) -> encodeInt   n, 16, true
Buffer.prototype.toUShort =     -> decodeInt   @, 16, false
Buffer.fromUShort         = (n) -> encodeInt   n, 16, false
Buffer.prototype.toInt    =     -> decodeInt   @, 32, true
Buffer.fromInt            = (n) -> encodeInt   n, 32, true
Buffer.prototype.toUInt   =     -> decodeInt   @, 32, false
Buffer.fromUInt           = (n) -> encodeInt   n, 32, false
Buffer.prototype.toLong   =     -> decodeInt   @, 64, true
Buffer.fromLong           = (n) -> encodeInt   n, 64, true
Buffer.prototype.toULong  =     -> decodeInt   @, 64, false
Buffer.fromULong          = (n) -> encodeInt   n, 64, false
Buffer.prototype.toFloat  =     -> decodeFloat @, 23, 8
Buffer.fromFloat          = (n) -> encodeFloat n, 23, 8
Buffer.prototype.toDouble =     -> decodeFloat @, 52, 11
Buffer.fromDouble         = (n) -> encodeFloat n, 52, 11

Buffer.prototype.reverse = ->
  rbuf = new Buffer @.length
  for i in [0...@.length]
    # p "#{i} -> #{@.length - i - 1}"
    @.copy rbuf, i, @.length - i - 1, @.length - i
  rbuf

Buffer.prototype.toHex = ->
  hex = ''
  for i in [0...@.length]
    hex += if @[i] < 16 then '0' + @[i].toString 16 else @[i].toString 16
  hex

module.exports =
  decodeInt: decodeInt
  encodeInt: encodeInt
