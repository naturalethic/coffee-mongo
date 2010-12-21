_int_min    = - Math.pow(2, 31)
_int_max    =   Math.pow(2, 31) - 1
_int_top    =   Math.pow 2, 32

float_to_buffer = (v) ->
  mLen  = 52
  eLen  = 11
  eMax  = (1 << eLen) - 1
  eBias = eMax >> 1
  s     = if v < 0 then 1 else 0
  v = Math.abs v
  if isNaN v or v == Infinity
    m = if isNaN v then 1 else 0
    e = eMax
  else
    e = Math.floor Math.log(v) / Math.LN2
    if v * (c = Math.pow(2, -e)) < 1
      e--
      c *= 2
    if v * c >= 2
      e++
      c /= 2
    if e + eBias >= eMax
      m = 0
      e = eMax
    else if e + eBias >= 1
      m = (v * c - 1) * Math.pow 2, mLen
      e = e + eBias
    else
      m = v * Math.pow(2, eBias - 1) * Math.pow(2, mLen)
      e = 0
  i = 0
  b = new Buffer 8
  while mLen >= 8
    b[i++] = m & 0xff
    m /= 256
    mLen -= 8
  e = (e << mLen) | m
  eLen += mLen
  while eLen > 0
    b[i++] = e & 0xff
    e /= 256
    eLen -= 8
  b[i - 1] |= s * 128
  b

buffer_to_float = (b) ->
  mLen  = 52
  eLen  = 11
  eMax  = (1 << eLen) - 1
  eBias = eMax >> 1
  nBits = -7
  i     = 7
  s     = b[i--]
  e     = s & ((1 << (-nBits)) - 1)
  s    >>= (-nBits)
  nBits += eLen
  while nBits > 0
    e = e * 256 + b[i--]
    nBits -= 8
  m = e & ((1 << (-nBits)) - 1)
  e >>= (-nBits)
  nBits += mLen
  while nBits > 0
    m = m * 256 + b[i--]
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

int32_to_buffer = (v) ->
  v = _int_min if v < _int_min
  v = _int_max if v > _int_max
  b = new Buffer 4
  for i in [0..3]
    b[i] = v & 0xff
    v >>= 8
  b

buffer_to_int32 = (b) ->
  v = 0
  f = 1
  for i in [0..3]
    v += b[i] * f
    f *= 256
  if v & _int_min
    v -= _int_top
  v

# 64-bit integer coding only supported reliably up to somewhere around (+/-) 2^53
int64_to_buffer = (v) ->
  neg = false
  neg = true if v < 0
  v = Math.abs v
  b = new Buffer 8
  s = v.toString(16)
  s = '0' + s while s.length < 16
  for i in [0..15] by 2
    b[i / 2] = parseInt(s.substr(i, 2), 16)
  b[0] |= 128 if neg
  b

buffer_to_int64 = (b) ->
  neg = b[0] & 128
  b[0] -= 128 if neg
  v = parseInt buffer_to_hex(b), 16
  b[0] += 128 if neg
  v = -v if neg
  v

buffer_to_hex = (b) ->
  ((if b[i] < 16 then '0' else '') + b[i].toString 16 for i in [0...b.length]).join('')

buffer_to_array = (b) ->
  b[i] for i in [0...b.length]

reverse_buffer = (b) ->
  t = new Buffer b.length
  b.copy t, b.length - i - 1, i, i + 1 for i in [0...b.length]
  t

_machine_id = int32_to_buffer(Math.floor(Math.random() * 0xffffff)).slice(0, 3)
_process_id = int32_to_buffer(process.pid).slice(0, 2)
_oid_index  = 0

class BSONBuffer extends Buffer
  toHex: ->
    buffer_to_hex @

  toArray: ->
    buffer_to_array @

  value: ->
    @toHex()

  toString: ->
    @value().toString()

class BSONKey extends BSONBuffer
  constructor: (value) ->
    if value instanceof Buffer
      for i in [0...value.length]
        if value[i] == 0
          super value.parent, i + 1, value.offset
          break
    else
      value = value.toString()
      super Buffer.byteLength(value) + 1
      @write value
      @[@length - 1] = 0

  value: ->
    @slice(0).toString 'utf8', 0, @length - 1

class BSONFloat extends BSONBuffer
  type: 0x01

  constructor: (value) ->
    if typeof value == 'number'
      value = float_to_buffer value
    super value.parent, 8, value.offset

  value: ->
    buffer_to_float @

class BSONString extends BSONBuffer
  type: 0x02

  constructor: (value) ->
    if value instanceof Buffer
      super value.parent, buffer_to_int32(value) + 4, value.offset
    else
      length = Buffer.byteLength(value) + 1
      super length + 4
      int32_to_buffer(length).copy @
      @write value, 4
      @[@length - 1] = 0

  value: ->
    @slice(0).toString 'utf8', 4, @length - 1

class BSONRegExp extends BSONBuffer
  type: 0x0B

  constructor: (value) ->
    if value instanceof Buffer
      nullEncounters = 0
      for i in [0...value.length]
        break if nullEncounters == 2
        nullEncounters++ if value[i] == 0
      super value.parent, i + 1, value.offset
    else
      str       = value.toString()
      lastSlash = str.lastIndexOf('/')
      pattern   = str.slice(1, lastSlash)
      flags     = str.slice(lastSlash + 1, str.length)
      super str.length
      @write pattern + '\u0000' + flags + '\u0000'

  value: ->
    pattern = null
    flags = null
    for i in [0...@length]
      if @[i] == 0
        if not pattern
          pattern = @slice(0, i).toString 'utf8'
        else
          flags = @slice(pattern.length + 1, i).toString 'utf8'
          break
    new RegExp pattern, flags

class BSONObjectID extends BSONBuffer
  type: 0x07

  constructor: (value) ->
    if value
      if value instanceof Buffer
        super value.parent, 12, value.offset
      else if typeof value == 'string' and /^[0-9a-fA-F]{24}$/.test
        super 12
        for i in [0..23] by 2
          @[i / 2] = parseInt(value.substr(i, 2), 16)
      else
        throw Error 'unsupported ObjectID initializer'
    else
      super 12
      reverse_buffer(int32_to_buffer(Math.floor(new Date().getTime() / 1000))).copy @
      _machine_id.copy @, 4
      _process_id.copy @, 7
      reverse_buffer(int32_to_buffer(_oid_index++)).slice(1).copy @, 9

  value: ->
    @toHex()

class BSONBoolean extends BSONBuffer
  type: 0x08

  constructor: (value) ->
    if value instanceof Buffer
      super value.parent, 1, value.offset
    else
      if value then super [1] else super [0]

  value: ->
    not not @[0]

class BSONDate extends BSONBuffer
  type: 0x09

  constructor: (value) ->
    value ?= new Date
    if value instanceof Date
      value = int64_to_buffer value.getTime()
    super value.parent, 8, value.offset

  value: ->
    new Date(buffer_to_int64 @)

class BSONNull extends BSONBuffer
  type: 0x0A

  constructor: (value) ->
    if value instanceof Buffer
      super value.parent, 0, value.offset
    else
      super 0

  value: ->
    null

class BSONInt32 extends BSONBuffer
  type: 0x10

  constructor: (value) ->
    if typeof value == 'number'
      value = int32_to_buffer value
    super value.parent, 4, value.offset

  value: ->
    buffer_to_int32 @

class BSONInt64 extends BSONBuffer
  type: 0x12

  constructor: (value) ->
    if typeof value == 'number'
      value = int64_to_buffer value
    super value.parent, 8, value.offset

  value: ->
    buffer_to_int64 @

class BSONElement extends BSONBuffer
  constructor: (args...) ->
    if args[0] instanceof Buffer
    else
      switch typeof args[1]
        when 'boolean'
          v = new BSONBoolean args[1]
        when 'number'
          if _int_min <= v <= _int_max
            v = new BSONInt32 args[1]
          else
            v = new BSONFloat args[1]
        when 'string'
          v = new BSONString args[1]
        when 'object'
          if args[1] instanceof Date
            v = new BSONDate args[1]
          else if args[1] instanceof Array
            v = new BSONArray args[1]
          else if args[1] instanceof BSONBuffer
            v = args[1]
          else if args[1] is null
            v = new BSONNull()
          else
            v = new BSONDocument args[1]
        when 'function'
          v = new BSONString args[1].toString()
        #when 'undefined'
        #  v = new BSONNull args[1]
      #console.log 'TYPE', typeof args[1] unless v
      throw Error 'unsupported bson value' if not v?
      k = new BSONKey args[0]
      super 1 + k.length + v.length
      @type = v.type
      @[0] = @type
      k.copy @, 1
      v.copy @, 1 + k.length

  key: ->
    return @_key if @_key?
    @_key = new BSONKey(@slice 1).value()

  value: ->
    return @_value if @_value
    @_value = (new _type[@type](@slice 1 + (new BSONKey(@slice 1)).length)).value()

class BSONDocument extends BSONBuffer
  type: 0x03

  constructor: (value) ->
    if value instanceof Buffer
      super value.parent, buffer_to_int32(value), value.offset
    else
      @_value = value
      els = []
      if @ instanceof BSONArray
        els.push new BSONElement i, v for v, i in value
      else
        els.push new BSONElement k, v for k, v of value
      length = 5
      length += el.length for el in els
      super length
      int32_to_buffer(length).copy @
      i = 4
      for el in els
        el.copy @, i
        i += el.length
      @[@length - 1] = 0

  value: ->
    return @_value if @_value
    @_value = if @ instanceof BSONArray then [] else {}
    i = 4
    while @[i]
      key = new BSONKey(@slice i + 1)
      throw Error 'unsupported bson value' if not _type[@[i]]
      val = new _type[@[i]] @slice i + key.length + 1
      if @ instanceof BSONArray
        @_value[parseInt key] = val.value()
      else
        @_value[key] = val.value()
      i += 1 + key.length + val.length
    @_value

class BSONArray extends BSONDocument
  type: 0x04

_type =
  0x01: BSONFloat
  0x02: BSONString
  0x03: BSONDocument
  0x04: BSONArray
  0x07: BSONObjectID
  0x08: BSONBoolean
  0x09: BSONDate
  0x0A: BSONNull
  0x0B: BSONRegExp
  0x10: BSONInt32
  0x12: BSONInt64

module.exports =
  _private:
    float_to_buffer: float_to_buffer
    buffer_to_float: buffer_to_float
    int32_to_buffer: int32_to_buffer
    buffer_to_int32: buffer_to_int32
    int64_to_buffer: int64_to_buffer
    buffer_to_int64: buffer_to_int64
    buffer_to_hex:   buffer_to_hex
    reverse_buffer:  reverse_buffer
    BSONKey:         BSONKey
    BSONFloat:       BSONFloat
    BSONString:      BSONString
    BSONRegExp:      BSONRegExp
    BSONObjectID:    BSONObjectID
    BSONBoolean:     BSONBoolean
    BSONDate:        BSONDate
    BSONNull:        BSONNull
    BSONRegExp:      BSONRegExp
    BSONInt32:       BSONInt32
    BSONInt64:       BSONInt64
    BSONElement:     BSONElement
    BSONDocument:    BSONDocument

  # public

  ObjectID:    BSONObjectID
  serialize:   (object) -> new BSONDocument object
  deserialize: (buffer) -> new BSONDocument(buffer).value()
  Key:         BSONKey
  Float:       BSONFloat
  String:      BSONString
  RegExp:      BSONRegExp
  ObjectID:    BSONObjectID
  Boolean:     BSONBoolean
  Date:        BSONDate
  Null:        BSONNull
  RegExp:      BSONRegExp
  Int32:       BSONInt32
  Int64:       BSONInt64
  Element:     BSONElement
  Document:    BSONDocument

