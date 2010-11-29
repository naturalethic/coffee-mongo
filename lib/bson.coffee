binary = require './binary'

_type_float = 0x01
_type_int = 0x10
_type_long = 0x12

# |	0x02" e_name string	UTF-8 string
# |	0x03" e_name document	Embedded document
# |	0x04" e_name document	Array
# |	0x05" e_name binary	Binary data
# |	0x06" e_name	Undefined — Deprecated
# |	0x07" e_name (byte*12)	ObjectId
# |	0x08" e_name 0x00"	Boolean "false"
# |	0x08" e_name 0x01"	Boolean "true"
# |	0x09" e_name int64	UTC datetime
# |	0x0A" e_name	Null value
# |	0x0B" e_name cstring cstring	Regular expression
# |	0x0C" e_name string (byte*12)	DBPointer — Deprecated
# |	0x0D" e_name string	JavaScript code
# |	0x0E" e_name string	Symbol
# |	0x0F" e_name code_w_s	JavaScript code w/ scope
# |	0x11" e_name int64	Timestamp
# |	0xFF" e_name	Min key
# |	0x7F" e_name	Max key

class ObjectID
  # XXX: _machine_id is supposed to be derived from the hostname
  _machine_id = Buffer.fromInt(Math.floor(Math.random() * 0xffffff)).slice(1)
  _process_id = Buffer.fromInt(process.pid).slice(2)
  _oid_index  = 0

  constructor: (@id) ->
    if not @id
      @id = new Buffer 12
      Buffer.fromInt(Math.floor(new Date().getTime() / 1000)).reverse().copy @id, 0, 0
      _machine_id.copy @id, 4, 0
      _process_id.copy @id, 7, 0
      Buffer.fromInt(_oid_index++).slice(1).reverse().copy @id, 9, 0
      # binary.encodeInt(_oid_index++, 24, false).reverse().copy @id, 9, 0

p Buffer.fromInt(1)
p new ObjectID
p new ObjectID
p new ObjectID
p new ObjectID

encodeKeyName = (value) ->
  length = Buffer.byteLength(value)
  buffer = new Buffer length + 1
  buffer.write value
  buffer[buffer.length - 1 ] = 0
  buffer

decodeKeyName = (buffer) ->
  for i in [0...buffer.length]
    if buffer[i] == 0
      return [i + 1, buffer.toString('utf8', 0, i)]

encodeString = (value) ->
  length = Buffer.byteLength(value)
  buffer = new Buffer length + 5
  Buffer.fromInt(length).copy buffer, 0, 0
  buffer.write value, 4
  buffer[buffer.length - 1 ] = 0
  buffer

decodeString = (buffer) ->
  length = buffer.toInt()
  buffer.toString 'utf8', 4, 4 + length

encodeBoolean = (value) ->
  if value then new Buffer [1] else new Buffer [0]

decodeBoolean = (buffer) ->
  not not buffer[0]

encodeInt = (value) ->
  Buffer.fromInt(value)

decodeInt = (buffer) ->
  buffer.toInt()

encodeLong = (value) ->
  Buffer.fromLong(value)

decodeLong = (value) ->
  buffer.toLong()

encodeFloat = (value) ->
  Buffer.fromDouble value

decodeFloat = (buffer) ->
  buffer.toDouble()

encodeDate = (value) ->
  Buffer.fromLong(value.getTime())

decodeDate = (buffer) ->
  new Date(buffer.toLong())

encodeBinary = (source) ->
  target = new Buffer source.length + 5
  Buffer.fromInt(source.length).copy target, 0, 0
  target[4] = 0
  source.copy target, 5, 0
  target

decodeBinary = (source) ->
  length = source.toInt()
  target = new Buffer length
  source.copy target, 0, 5, 5 + length
  target

encodeObjectID = (value) ->
  id = new Buffer 12
  value.id.copy id, 0, 0, 11
  id

decodeObjectID = (buffer) ->
  id = new Buffer 12
  buffer.copy id, 0, 0, 11
  new ObjectID id

encodeDocument = (value) ->
  items = []
  length = 0
  if value instanceof Array
    for val, i in value
      item = encodeElement String(i), val
      length += item.length
      items.push item
  else
    for key, val of value
      item = encodeElement key, val
      length += item.length
      items.push item
  buffer = new Buffer length + 5
  Buffer.fromInt(length).copy buffer, 0, 0
  i = 4
  for item in items
    item.copy buffer, i, 0, item.length
    i += item.length
  buffer[buffer.length - 1] = 0
  buffer

decodeDocument = (buffer, array) ->
  length = buffer.toInt()
  i = 4
  if array
    value = []
  else
    value = {}
  while i < buffer.length - 1
    [size, type, key, val] = decodeElement buffer.slice i
    if array
      value.push val
    else
      value[key] = val
    i += size
  value

encodeElement = (key, val) ->
  switch typeof val
    when 'number'
      if Math.floor(val) == val
        if _min_int <= val <= _max_int
          type = _type_int
          buf = Buffer.fromInt val
        else
          type = _type_long
          buf = Buffer.fromLong val
      else
        type = _type_float
        buf = Buffer.fromDouble val
  key = encodeKeyName key
  buffer = new Buffer 1 + key.length + buf.length
  buffer[0] = type
  key.copy buffer, 1, 0
  buf.copy buffer, 1 + key.length, 0
  buffer

decodeElement = (buffer) ->
  type        = buffer[0]
  [size, key] = decodeKeyName buffer.slice 1
  buffer      = buffer.slice 1 + size
  switch type
    when _type_int
      val = buffer.toInt()
    when _type_long
      val = buffer.toLong()
    when _type_float
      val = buffer.toFloat()
  [key, val]

# p decodeElement(encodeElement('foo', 1.1))
