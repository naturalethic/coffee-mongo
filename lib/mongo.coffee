try
  util   = require 'util'
catch error
  util   = require 'sys'
log      = (args...) -> util.puts(a) for a in args
inspect  = (args...) -> log(util.inspect(a)) for a in args
_bson    = require './vendor/bson'
binary   = require './vendor/binary'
net      = require 'net'
ObjectID = _bson.ObjectID
bson     = _bson.BSON

class Database
  constructor: (@name, @host, @port) ->
    @host ?= 'localhost'
    @port ?= 27017
    @connections = []

  # Close all open connections.  Use at your own risk.
  @close: ->
    for connection in @connections
      connection.close()
    @connections = []

  connection: (next) ->
    for i in [0...@connections.length]
      connection = @connections[i]
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
      connection.send (@compose '$cmd', 2004, 0, 0, 1, { getLastError: 1 }), (data) =>
        connection.release()
        errors = @decompose data
        log 'Mongo error: ' + errors[0].err if errors[0].err?
        next(document._id) if next?

  update: (collection, selector, update, next) ->
    @connection (connection) =>
      connection.retain()
      connection.send (@compose collection, 2001, 0, 0, selector, update)
      connection.send (@compose '$cmd', 2004, 0, 0, 1, { getLastError: 1 }), (data) =>
        connection.release()
        errors = @decompose data
        log 'Mongo error: ' + errors[0].err if errors[0].err?
        next(errors[0].n) if next?

  query: (collection, selector, next) ->
    @connection (connection) =>
      connection.retain()
      connection.send (@compose collection, 2004, 0, 0, 0, selector), (data) =>
        documents = @decompose data
        connection.send (@compose '$cmd', 2004, 0, 0, 1, { getLastError: 1 }), (data) =>
          connection.release()
          errors = @decompose data
          log 'Mongo error: ' + errors[0].err if errors[0].err?
          next(documents) if next?

  remove: (collection, selector, next) ->
    @connection (connection) =>
      connection.retain()
      connection.send (@compose collection, 2006, 0, 0, selector)
      connection.send (@compose '$cmd', 2004, 0, 0, 1, { getLastError: 1 }), (data) =>
        connection.release()
        errors = @decompose data
        log 'Mongo error: ' + errors[0].err if errors[0].err?
        next() if next?

  compose: (collection, code, flags, items...) ->
    data = binary.fromInt(flags) + binary.encode_cstring(@name + '.' + collection)
    for i in [0...items.length]
      if typeof items[i] == 'object'
        data += bson.serialize items[i]
      else
        data += binary.fromInt items[i]
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
      for c in [0...count]
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

# database = new Database 'test', 'localhost', 27017
# database._query 'sample', { }, (result) ->
  # inspect result
# database.query 'sample', { }, (result) ->
#   inspect result
# database.query '$cmd', { buildInfo: 1 }, (result) ->
#   inspect result
# database.query 'sample', { _id: new ObjectID('1d50bf4cc0a7ff5d00000000') }, (result) ->
  # inspect result

# database.update 'sample', { hello: 'world' }, { $set: { hello: 'YOU' } }, ->
#   log 'ok'
# database.update 'sample', { _id: '4cc20a2cc6c53ab40e0a6ceb' }, { $set: { hello: 'YOU' } }, ->
# database.update 'sample', { hello: 'world' }, { $set: { hello: 'YOU' } }, ->

    # database.query 'sample', { }, (result) ->
  #   inspect result
# database.insert 'sample', { 'hello': 'world' }, ->
#   log 'ok'
  # database.insert 'sample', { 'hello': 'world' }, ->
  #   database.insert 'sample', { 'hello': 'world' }
# connection = new Connection 'localhost', 27017
# connection.open ->
#   data = binary.fromInt(0) + binary.encode_cstring('test.sample') + bson.serialize({ 'hello': 'world' })
#   size = data.length + 4 * 4
#   data = binary.fromInt(size) + binary.fromInt(0) + binary.fromInt(0) + binary.fromInt(2002) + data
#   inspect data
#   connection.send data

# congo = require 'congo'
# congo.use 'test'
# congo.load 'sample', new ObjectID('1d50bf4cc0a7ff5d00000000')

# mongodb = require 'mongodb'
# db = new mongodb.Db('test', new mongodb.Server('localhost', 27017, { native_parser: true }))
# query = new mongodb.QueryCommand db, 'sample', 0, 0, 0, { _id: new ObjectID('1d50bf4cc0a7ff5d00000000') }, null
# inspect query.toBinary()
# insert = new mongodb.InsertCommand db, 'sample', false
# insert.add { 'hello': 'world' }
# data0 = insert.toBinary()
# inspect data0

# data = binary.fromInt(0) + binary.encode_cstring('sample') + bson.serialize({ 'hello': 'world' })
# size = data.length + 4 * 4
# data = binary.fromInt(size) + binary.fromInt(0) + binary.fromInt(0) + binary.fromInt(2002) + data
# inspect data

# inspect data == data0


# mongodb = require 'mongodb'
# db = new mongodb.Db('test', new mongodb.Server('localhost', 27017, { native_parser: true }))
# db.open ->
#   db.createCollection 'sample', (err, collection) ->
#     # collection.find { hello: 'world' }, (documents) ->
#     collection.find { }, (err, cursor) ->
#       cursor.toArray (err, documents) ->
#         inspect documents
