try
  util   = require 'util'
catch error
  util   = require 'sys'
log      = (args...) -> util.puts(a) for a in args
inspect  = (args...) -> log(util.inspect(a, true, null)) for a in args
_bson    = require './vendor/bson'
binary   = require './vendor/binary'
net      = require 'net'
ObjectID = _bson.ObjectID
bson     = _bson.BSON

class Database
  constructor: (@name, args...) ->
    @host = 'localhost'
    @port = 27017
    @idfactory = -> new ObjectID
    @connections = []
    for arg in args
      switch typeof arg
        when 'string'
          @host = arg
        when 'number'
          @port = arg
        when 'function'
          @idfactory = arg

  # Close all open connections.  Use at your own risk.
  @close: ->
    for connection in @connections
      connection.close()
    @connections = []

  connection: (next) ->
    for connection, i in @connections
      if connection.available
        log 'Connection: ' + i if process.env.DEBUG?
        next connection
        return
    log 'Connection: ' + @connections.length if process.env.DEBUG?
    connection = new Connection @host, @port
    @connections.push connection
    connection.open -> next connection

  insert: (collection, document, next) ->
    document._id = new ObjectID()
    @connection (connection) =>
      connection.retain()
      connection.send (@compose collection, 2002, 0, document)
      @last_error connection, (error) ->
        connection.release()
        log 'Mongo error: ' + error.err if error.err?
        next(document._id) if next?

  update: (collection, query, update, next) ->
    @connection (connection) =>
      connection.retain()
      connection.send (@compose collection, 2001, 0, 0, query, update)
      @last_error connection, (error) ->
        connection.release()
        log 'Mongo error: ' + error.err if error.err?
        next() if next?

  find: (collection, query, args..., next) ->
    path = if args.length > 0 then { (args[0]): 1 } else {}
    @connection (connection) =>
      connection.retain()
      connection.send (@compose collection, 2004, 0, 0, 0, query, path), (data) =>
        documents = @decompose data
        @last_error connection, (error) ->
          connection.release()
          log 'Mongo error: ' + error.err if error.err?
          next(documents) if next?

  find_one: (collection, query, args..., next) ->
    @find collection, query, args..., (documents) ->
      if documents.length > 0 then next documents[0] else next null

  exists: (collection, id, path, next) ->
    @find collection, { _id: id, (path): { $exists: true } }, '_id', (documents) ->
      if documents.length > 0 then next true else next false

  remove: (collection, query, next) ->
    @connection (connection) =>
      connection.retain()
      connection.send (@compose collection, 2006, 0, 0, query)
      connection.send (@compose '$cmd', 2004, 0, 0, 1, { getLastError: 1 }), (data) =>
        connection.release()
        errors = @decompose data
        log 'Mongo error: ' + errors[0].err if errors[0].err?
        next() if next?

  clear: (collection, next) ->
    @remove collection, {}, next

  last_error: (connection, next) ->
    connection.send (@compose '$cmd', 2004, 0, 0, 1, { getLastError: 1 }), (data) =>
      next (@decompose data)[0] if next?

  command: (command, options, next) ->
    options.__command__ = 'findandmodify'
    @connection (connection) =>
      connection.retain()
      connection.send (@compose '$cmd', 2004, 0, 0, 1, options), (data) =>
        connection.release()
        document = (@decompose data)[0]
        if document['bad cmd']?
          log 'Mongo error: ' + document.errmsg
          inspect document['bad cmd']
          next null if next?
        else if document['$err']?
          log 'Mongo error: ' + document['$err']
          next null if next?
        else
          next document if next?

  modify: (collection, options, next) ->
    options.findandmodify = collection
    options.query  ?= {}
    options.sort   ?= {}
    options.remove ?= false
    options.update ?= {}
    options.new    ?= false
    options.fields ?= {}
    options.upsert ?= false
    @command 'findandmodify', options, (document) ->
      next document.value

  sequence: (collection, id, args..., next) ->
    key = if args.length > 0 then args[0] else '_root'
    @modify collection, { new: true, query: { _id: id }, update: { $inc: { ('_sequence.' + key): 1 }}, fields: { ('_sequence.' + key): 1 }}, (result) ->
      next result._sequence[key]

  compose: (collection, code, flags, items...) ->
    data = binary.fromInt(flags) + binary.encode_cstring(@name + '.' + collection)
    for item in items
      if typeof item == 'object'
        data += bson.serialize item
      else
        data += binary.fromInt item
    binary.fromInt(data.length + 4 * 4) + binary.fromInt(0) + binary.fromInt(0) + binary.fromInt(code) + data

  decompose: (data) ->
    i = 4 * 3
    code = binary.toInt(data.substr i)
    i += 4
    if code == 1
      flags = binary.toInt(data.substr i)
      i += 4
      cursor = binary.toInt64(data.substr i)
      i += 8
      start = binary.toInt(data.substr i)
      i += 4
      count = binary.toInt(data.substr i)
      i += 4
      documents = []
      while count--
        documents.push bson.deserialize(data.substr i)
        i += binary.toInt(data.substr i)
    else
      log 'Unsupported response', code
    documents

class Connection
  constructor: (@host, @port) ->
    @stream = null
    @available = false
    @buffer = ''

  retain: ->
    @available = false

  release: ->
    @available = true

  open: (next) ->
    @stream = net.createConnection @port, @host
    @stream.addListener 'connect', =>
      next()
    @stream.addListener 'data', (data) =>
      @buffer += data.toString 'binary'
      if binary.toInt(@buffer) == @buffer.length
        @next(@buffer) if @next
        @buffer = ''
    @stream.addListener 'close', (err) =>
      log 'closed'
    @stream.addListener 'end', =>
      log 'end'
    @stream.addListener 'close', =>
      log 'close'
    @stream.addListener 'timeout', =>
      log 'timeout'

  send: (data, next) ->
    @next = next
    @stream.write data, 'binary'

  close: ->
    @stream.end()

module.exports =
  ObjectID: ObjectID
  Database: Database
