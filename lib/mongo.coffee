net      = require 'net'
util     = require 'util'
put      = (args...) -> util.print(a) for a in args
puts     = (args...) -> put(a + '\n') for a in args
p        = (args...) -> puts(util.inspect(a, true, null)) for a in args
binary   = require './vendor/binary'
_bson    = require './vendor/bson'
ObjectID = _bson.ObjectID
bson     = _bson.BSON

# Represents a Mongo database
#
# Takes:
#   name      : name of the database
#   host      : host (optional, defaults to localhost)
#   port      : port (optional, defaults to 27017)
#   idfactory : a function that provides ids (optional, defaults to ObjectIDs)
#
# An idfactory has the following interface:
#
# Takes:
#   collection : collection name
#
# Gives:
#   error      : error, if any
#   id         : a new unique id for the provided collection
class Database
  constructor: (@name, args...) ->
    @host = 'localhost'
    @port = 27017
    @idfactory = (collection, next) -> next null, new ObjectID
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
  close: ->
    for connection in @connections
      connection.close()
    @connections = []

  # XXX: Needs limits and queuing
  # Pull a connection from the pool, or create a new one.
  connection: (next) ->
    for connection, i in @connections
      if connection.available
        puts 'Connection: ' + i if process.env.DEBUG?
        next null, connection
        return
    puts 'Connection: ' + @connections.length if process.env.DEBUG?
    connection = new Connection @host, @port
    @connections.push connection
    connection.open next

  # Insert a document into a collection
  #
  # Takes:
  #   collection : collection name
  #   document   : the document
  #
  # Gives:
  #   error      : error
  #   document   : the document with '_id' populated
  insert: (collection, document, next) ->
    idfactory = @idfactory
    if document._id
      idfactory = (_, next) -> next null, document._id
    idfactory collection, (error, id) =>
      document._id = id
      @connection (error, connection) =>
        connection.retain()
        connection.send (@compose collection, 2002, 0, document)
        @last_error connection, (error, mongo_error) ->
          connection.release()
          next(mongo_error, document) if next

  # Updates documents in a collection
  #
  # Takes:
  #   collection : collection name
  #   query      : query document (optional - if absent, updates all documents)
  #   update     : document to replace found documents
  #
  # Gives:
  #   error      : error
  update: (collection, args...) ->
    next   = args.pop()
    update = args.pop() or {}
    query  = args.pop() or {}
    @connection (error, connection) =>
      connection.retain()
      connection.send (@compose collection, 2001, 0, 0, query, update)
      @last_error connection, (error, mongo_error) ->
        connection.release()
        next mongo_error if next

  # Find documents in a collection
  #
  # Takes:
  #   collection : collection name
  #   query      : query document (optional - if absent, gives all documents)
  #
  # Gives:
  #   error      : error
  #   documents  : array of found documents
  find: (collection, args...) ->
    next  = args.pop()
    query = args.pop() or {}
    @connection (error, connection) =>
      connection.retain()
      connection.send (@compose collection, 2004, 0, 0, 0, query), (error, data) =>
        documents = @decompose data
        @last_error connection, (error, mongo_error) ->
          connection.release()
          next mongo_error, documents if next

  # Find a single document in a collection
  #
  # Takes:
  #   collection : collection name
  #   query      : query document (optional - if absent, gives first overall document)
  #
  # Gives:
  #   error      : error
  #   document   : the found document, or null
  find_one: (collection, args...) ->
    next  = args.pop()
    query = args.pop() or {}
    @find collection, query, (error, documents) ->
      if documents.length > 0 then next error, documents[0] else next error, null

  # XXX: Come back to these for result limits (path)
  # find: (collection, query, args..., next) ->
  #   path = if args.length > 0 then { (args[0]): 1 } else {}
  #   @connection (connection) =>
  #     connection.retain()
  #     connection.send (@compose collection, 2004, 0, 0, 0, query, path), (data) =>
  #       documents = @decompose data
  #       @last_error connection, (error) ->
  #         connection.release()
  #         puts 'Mongo error: ' + error.err if error.err?
  #         next(documents) if next
  # find_one: (collection, query, args..., next) ->
  #   @find collection, query, args..., (documents) ->
  #     if documents.length > 0 then next documents[0] else next null

  # exists: (collection, id, path, next) ->
  #   @find collection, { _id: id, (path): { $exists: true } }, '_id', (documents) ->
  #     if documents.length > 0 then next true else next false

  # Remove all documents from a collection
  #
  # Takes:
  #   collection : collection name
  #
  # Gives:
  #   error      : error
  clear: (collection, next) ->
    @remove collection, {}, next

  # Remove documents from a collection matching a query
  #
  # Takes:
  #   collection : collection name
  #   query      : query document (optional - if absent, removes all documents)
  #
  # Gives:
  #   error      : error
  remove: (collection, args...) ->
    next  = args.pop()
    query = args.pop() or {}
    @connection (error, connection) =>
      connection.retain()
      connection.send (@compose collection, 2006, 0, 0, query)
      connection.send (@compose '$cmd', 2004, 0, 0, 1, { getLastError: 1 }), (error, data) =>
        connection.release()
        next @decompose_error(data) if next

  # Check server for last error, if any
  last_error: (connection, next) ->
    connection.send (@compose '$cmd', 2004, 0, 0, 1, { getLastError: 1 }), (error, data) =>
      next error, @decompose_error(data) if next

  # Decompose a last_error response
  decompose_error: (data) ->
    error = (@decompose data)[0]
    if error.err then { code: error.code, message: error.err } else null

  # Remove documents from a collection matching a query
  #
  # Takes:
  #   collection : collection name
  #   options    : (XXX: document this)
  #
  # Gives:
  #   error      : error
  #   document   : the modified document
  modify: (collection, options, next) ->
    options.findandmodify = collection
    options.query  ?= {}
    options.sort   ?= {}
    options.remove ?= false
    options.update ?= {}
    options.new    ?= false
    options.fields ?= {}
    options.upsert ?= false
    @command 'findandmodify', options, (error, document) ->
      next error, document.value

  command: (command, options, next) ->
    options.__command__ = 'findandmodify'
    @connection (error, connection) =>
      connection.retain()
      connection.send (@compose '$cmd', 2004, 0, 0, 1, options), (error, data) =>
        connection.release()
        if next
          document = (@decompose data)[0]
          if document['bad cmd']?
            next document, null
          else if document['$err']?
            next document, null
          else
            next null, document

  # XXX: Doesn't go in here, move sequences somewhere else
  # sequence: (key, next) ->
  #   proceed = =>
  #     @modify '__sequence__', { new: true, query: { key: key }, update: { $inc: { value: 1 }}, fields: { value: 1 }}, (result) =>
  #       next result.value
  #   @find_one '__sequence__', { key: key }, (document) =>
  #     if not document
  #       @insert '__sequence__', { _id: new ObjectID, key: key }, (id) =>
  #         proceed()
  #     else
  #       proceed()

  # Compose a mongo binary message
  compose: (collection, code, flags, items...) ->
    data = binary.fromInt(flags) + binary.encode_cstring(@name + '.' + collection)
    for item in items
      if typeof item == 'object'
        data += bson.serialize item
      else
        data += binary.fromInt item
    binary.fromInt(data.length + 4 * 4) + binary.fromInt(0) + binary.fromInt(0) + binary.fromInt(code) + data

  # Deompose a mongo binary message
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
      puts 'Unsupported response', code
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
    @stream.on 'connect', =>
      next null, @
    @stream.on 'data', (data) =>
      @buffer += data.toString 'binary'
      if binary.toInt(@buffer) == @buffer.length
        @next null, @buffer if @next
        @buffer = ''
    @stream.on 'close', =>
    @stream.on 'end', =>
    @stream.on 'close', =>
    @stream.on 'timeout', =>

  send: (data, next) ->
    @next = next
    @stream.write data, 'binary'

  close: ->
    @stream.end()

module.exports =
  ObjectID: ObjectID
  Database: Database
