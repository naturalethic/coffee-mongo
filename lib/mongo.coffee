net      = require 'net'
bson     = require './bson'

# Represents a Mongo database
#
# Takes:
#   name        : name of the database
#   options     : options hash
#     host      :   default 'localhost'
#     port      :   default 27017
#     limit     :   default limit for find responses (default 100)
#     hex       :   uses hex strings instead of binary ObjectID
#     idfactory :   a function that provides ids (default to ObjectID)
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
  constructor: (@name, options) ->
    options    = options or {}
    @host      = options.localhost or 'localhost'
    @port      = options.port      or 27017
    @limit     = options.limit     or 100
    @idfactory = options.idfactory
    if not @idfactory
      if options.hex
        @idfactory = (collection, next) -> next null, new bson.ObjectID().toHex()
      else
        @idfactory = (collection, next) -> next null, new bson.ObjectID()
    @connections = []

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
      @insert_without_id collection, document, next

  insert_without_id: (collection, document, next) ->
    @connection (error, connection) =>
      connection.retain()
      connection.send (@compose collection, 2002, 0, document)
      @last_error connection, (error, mongo_error) ->
        connection.release()
        next(mongo_error, document) if next

  # Updates documents in a collection
  #
  # Updates always are assumed multi=true.  Upserts are not supported because
  # we always want to specify our own _id.
  #
  # Takes:
  #   collection : collection name
  #   query      : query document (optional - if absent, updates all documents)
  #   update     : update operations document
  #
  # Gives:
  #   error      : error
  update: (collection, args..., next) ->
    update  = args.pop() or {}
    query   = args.pop() or {}
    @connection (error, connection) =>
      connection.retain()
      connection.send (@compose collection, 2001, 0, 2, query, update)
      @last_error connection, (error, mongo_error) ->
        connection.release()
        next mongo_error if next

  # Find documents in a collection
  #
  # Takes:
  #   collection : collection name
  #   query      : query document (optional - if absent, gives all documents)
  #   options    : options hash
  #     limit    :   max records returned
  #     skip     :   number of records to skip
  #     fields   :   specifies particular fields to return (can pass hash or array)
  #     sort     :   sort document
  #
  # Gives:
  #   error      : error
  #   documents  : array of found documents
  find: (collection, args..., next) ->
    options = if args.length == 2 then args.pop() else {}
    query   = args.pop() or {}
    options.limit  ?= @limit
    options.skip   ?= 0
    fields          = {}
    if options.fields
      if options.fields instanceof Array
        for field in options.fields
          fields[field] = 1
      else
        fields = options.fields
    if options.sort
      query =
        $query:   query
        $orderby: options.sort
    @connection (error, connection) =>
      connection.retain()
      connection.send (@compose collection, 2004, 0, options.skip, options.limit, query, fields), (error, data) =>
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
  find_one: (collection, args..., next) ->
    options = if args.length == 2 then args.pop() else {}
    query   = args.pop() or {}
    options.limit = 1
    @find collection, query, options, (error, documents) ->
      if documents.length > 0 then next error, documents[0] else next error, null

  # Remove documents from a collection matching a query
  #
  # Takes:
  #   collection : collection name
  #   query      : query document (optional - if absent, removes all documents)
  #
  # Gives:
  #   error      : error
  remove: (collection, args..., next) ->
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

  # Performs atomic find/modify operation on a single document
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
      if document and document.errmsg
        error = { code: document.code, message: document.errmsg }
        document = null
      next(error, (if document then document.value else null)) if next

  # Add indexes against specified keys, ignoring those that already exist.
  #
  # Takes:
  #   collection : collection name
  #   keys       : hash of keys to index (may be deep), value denotes unique
  #
  # Gives:
  #   error      : error
  index: (collection, keys, next) ->
    count = 0
    count++ for k of keys
    for key, unique of keys
      document          = {}
      document.name     = key.replace('.', '_') + '_'
      document.ns       = @name + '.' + collection
      document.unique   = !!unique
      document.key      = {}
      document.key[key] = 1
      @insert_without_id 'system.indexes', document, (error, document) =>
        next error if next and (error or not --count)

  # Removes index for specified key
  #
  # Takes:
  #   collection : collection name
  #   key        : key for which to remove index
  #
  # Gives:
  #   error      : error
  removeIndex: (collection, key, next) ->
    options = {}
    options.dropIndexes = collection
    options.index       = {}
    options.index[key]  = 1
    @command 'dropIndexes', options, (error, document) ->
      if document and document.errmsg
        error = { code: document.code, message: document.errmsg }
        document = null
      next(error, (if document then document.value else null)) if next

  # Creates a collection.  This is automatic, so only need to call this if special options are needed.
  #
  # Takes:
  #   collection : collection name
  #   options    : (optional)
  #     capped   :   true if a capped collection
  #     size     :   cap at number of bytes
  #     max      :   cap at number of objects (requires size also)
  #
  # Gives:
  #   error      : error
  #   document   : result document
  create: (collection, options, next) ->
    options ?= {}
    options = { create: collection, capped: options.capped, size: options.size, max: options.max }
    @command 'create', options, (error, document) ->
      if document and document.errmsg
        error = { code: document.code, message: document.errmsg }
        document = null
      next(error, (if document then document.value else null)) if next

  # Drops a collection
  #
  # Takes:
  #   collection : collection name
  #
  # Gives:
  #   error      : error
  #   document   : result document
  drop: (collection, next) ->
    @command 'drop', { drop: collection}, (error, document) ->
      if document and document.errmsg
        error = { code: document.code, message: document.errmsg }
        document = null
      next(error, (if document then document.value else null)) if next

  # Runs a command
  #
  # Takes:
  #   command    : command name, must also be set in the options
  #   document   : the full command document
  #
  # Gives:
  #   error      : error
  #   document   : result document
  command: (command, document, next) ->
    # Rebuild document object to ensure command is first in key order
    cdoc = {}
    cdoc[command] = if document[command]? then document[command] else 1
    delete document[command]
    for k, v of document
      cdoc[k] = v
    @connection (error, connection) =>
      connection.retain()
      connection.send (@compose '$cmd', 2004, 0, 0, 1, cdoc), (error, data) =>
        connection.release()
        if next
          document = (@decompose data)[0]
          if document['bad cmd']?
            next document, null
          else if document['$err']?
            next document, null
          else
            next null, document

  # Compose a mongo binary message
  compose: (collection, code, payload...) ->
    composition = [
      new bson.Int32 0                         # message length
      new bson.Int32 0                         # request id
      new bson.Int32 0                         # response to id
      new bson.Int32 code                      # op code
      new bson.Int32 payload.shift()           # (depends on op)
      new bson.Key   @name + '.' + collection  # dbname.collectionname
    ]
    for item in payload
      if item instanceof Array
        composition.push new bson.Document item[0], item[1]
      else if typeof item == 'object'
        composition.push new bson.Document item
      else
        composition.push new bson.Int32 item
    length = 0
    for item in composition
      length += item.length
    composition[0] = new bson.Int32 length     # update the message length
    buffer = new Buffer length
    i = 0
    for item in composition
      item.copy buffer, i
      i += item.length
    buffer

  # Decompose a mongo binary message
  decompose: (buffer) ->
    i = 4 * 3
    code = (new bson.Int32 buffer.slice i).value()
    i += 4
    if code == 1
      flags = (new bson.Int32 buffer.slice i).value()
      i += 4
      cursor = (new bson.Int64 buffer.slice i).value()
      i += 8
      start = (new bson.Int32 buffer.slice i).value()
      i += 4
      count = (new bson.Int32 buffer.slice i).value()
      i += 4
      documents = []
      while count--
        document = new bson.Document buffer.slice i
        documents.push document.value()
        i += document.length
    else
      throw Error "unsupported response code: #{code}"
    documents

_buffer_grow_size = 10000

class Connection
  constructor: (@host, @port) ->
    @stream = null
    @available = false
    @buffer = new Buffer _buffer_grow_size
    @marker = 0

  retain: ->
    @available = false

  release: ->
    @available = true

  open: (next) ->
    @stream = net.createConnection @port, @host
    @stream.on 'connect', =>
      next null, @
    @stream.on 'data', (data) =>
      while @buffer.length < @marker + data.length
        buffer = new Buffer @buffer.length + _buffer_grow_size
        @buffer.copy buffer
        @buffer = buffer
      data.copy @buffer, @marker
      @marker += data.length
      if @marker > 3 and new bson.Int32(@buffer).value() == @marker
        @next null, @buffer if @next
        @marker = 0
    @stream.on 'close', =>
    @stream.on 'end', =>
    @stream.on 'close', =>
    @stream.on 'timeout', =>

  send: (data, next) ->
    @next = next
    @stream.write data

  close: ->
    @stream.end()

module.exports =
  # ObjectID: ObjectID
  Database: Database
