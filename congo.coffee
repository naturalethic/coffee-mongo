# Congo is a modeling interface to MongoDB written in and relying on CoffeeScript and Node.js.
#
# Copyright (c) 2010 Joshua Kifer
#
# Dependencies:
#  - http://github.com/christkv/node-mongodb-native

sys     = require 'sys'
log     = (s) -> sys.puts(s)
inspect = (s) -> log(sys.inspect(s, true, null))

mongodb = require 'mongodb'

DEBUG = false

class CongoType
  constructor: (@number, @name) ->

__type__ =
  String:   new CongoType 2,  'String'
  Identity: new CongoType 7,  'Identity'
  Date:     new CongoType 9,  'Date'
  Integer:  new CongoType 18, 'Integer'

ObjectID = if mongodb.BSONNative then mongodb.BSONNative.ObjectID else mongdb.BSONPure.ObjectID

class Model
  constructor: (initial, next) ->
    if initial instanceof Function
      next = initial
      initial = null
    initial ?= {}
    @__parent__ = null
    @__key__    = null
    @__index__  = null
    @__types__  = {}
    @__values__ = {}
    for all key, val of this
      continue if key in ['constructor', '__parent__', '__key__', '__index__', '__types__', '__values__']
      if (( val instanceof CongoType or val.prototype instanceof Model ) or
          ( val instanceof Array and val.length == 1 and ( val[0] instanceof CongoType or val[0].prototype instanceof Model )))
        @__types__[key] = val
        if initial[key]?
          @__values__[key] = initial[key]
        else if val instanceof Array
          @__values__[key] = []
        else
          @__values__[key] = null
        obj = this
        define_gs = (key) ->
          obj.__defineGetter__ key, ->
            obj.get key
          obj.__defineSetter__ key, (val) ->
            obj.set key, val
        define_gs key
    next this if next?

  # Return an object tree minus all the meta information
  dehydrate: ->
    document = {}
    for key, val of @__values__
      if val instanceof Array
        document[key] = []
        for item in val
          if item instanceof Model
            document[key].push item.dehydrate()
          else
            document[key].push item
      else if val instanceof Model
        document[key] = val.dehydrate()
      else
        document[key] = val
    document

  # Populate this object with the passed document
  hydrate: (document, next) ->
    log '[ Hydrating ] ' + this.constructor.name if DEBUG
    # Set all scalar values
    for key, type of @__types__
      if type instanceof Array
        type = type[0]
        @__values__[key] = []
      else
        @__values__[key] = null
      if document[key]? and not (type instanceof Function and type.prototype instanceof Model)
        if document[key] instanceof Array
          for val in document[key]
            @__values__[key].push val
        else
          @__values__[key] = document[key]
    # Grab a count (hydrate_size) of all subdocuments that need hydrated, so we know when to call next
    hydrate_done = 0
    hydrate_size = 0
    for key, type of @__types__
      type = type[0] if type instanceof Array
      if document[key]? and type instanceof Function and type.prototype instanceof Model
        if document[key] instanceof Array
          hydrate_size += document[key].length
        else
          hydrate_size += 1
    # Set values and hydrate subdocuments
    for key, type of @__types__
      type = type[0] if type instanceof Array
      if document[key]? and type instanceof Function and type.prototype instanceof Model
        if document[key] instanceof Array
          for val in document[key]
            new type (object) =>
              @__values__[key].push object
              object.hydrate val, ->
                hydrate_done += 1
                next() if hydrate_done == hydrate_size
        else
          new type (object) =>
            @__values__[key] = object
            object.hydrate document[key], ->
              hydrate_done += 1
              next() if hydrate_done == hydrate_size
    next() if hydrate_done == hydrate_size

  # Provide meta information regarding parent/child relationship
  relate: (key, val, index) ->
    if val instanceof Model
      log '[ Relating  ] ' + this.constructor.name + '.' + key if DEBUG
      val.__parent__ = this
      val.__key__    = key
      val.__index__  = index if index?

  get: (key) ->
    @__values__[key]

  set: (key, val, next) ->
    log '[ Setting   ] ' + this.constructor.name + '.' + key if DEBUG
    @__values__[key] = val
    @relate key, val
    if @__parent__
      @__parent__.ascend_set this, key, val, next
    else
      next() if next?

  push: (key, val, next) ->
    this[key].push val
    @relate key, val, this[key].length - 1
    if @__parent__
      @__parent__.ascend_push this, key, val, next
    else if this instanceof Collection
      Congo.push this, key, val, next
    else
      next() if next?

  ascend_push: (child, key, val, next) ->
    if @__parent__
      if child.__index__?
        log '[ Ascending ] ' + child.__key__ + '.' + child.__index__ + '.' + key if DEBUG
        @__parent__.ascend_push this, child.__key__ + '.' + child.__index__ + '.' + key, val, next
      else
        log '[ Ascending ] ' + child.__key__ + '.' + key if DEBUG
        @__parent__.ascend_push this, child.__key__ + '.' + key, val, next
    else
      next() if next?

  # Signal up the parent chain to the collection to save the model
  ascend_set: (child, key, val, next) ->
    if @__parent__
      if child.__index__?
        log '[ Ascending ] ' + child.__key__ + '.' + child.__index__ + '.' + key if DEBUG
        @__parent__.ascend_set this, child.__key__ + '.' + child.__index__ + '.' + key, val, next
      else
        log '[ Ascending ] ' + child.__key__ + '.' + key if DEBUG
        @__parent__.ascend_set this, child.__key__ + '.' + key, val, next
    else
      next() if next?

class Collection extends Model
  _id: __type__.Identity

  @extended: (subclass) ->
    subclass.clear = (next) ->
      Congo.clear subclass, next
    subclass.load = Collection.load

  constructor: (initial, next) ->
    if initial instanceof Function
      next = initial
      initial = null
    super initial
    if not @__values__._id?
      Congo.create this, => next this
    else if next?
      next this

  ascend_push: (child, key, val, next) ->
    if child.__index__?
      log '[ Storing   ] ' + child.__key__ + '.' + child.__index__ + '.' + key if DEBUG
      Congo.push this, child.__key__ + '.' + child.__index__ + '.' + key, val, next
    else
      log '[ Storing   ] ' + child.__key__ + '.' + key if DEBUG
      Congo.push this, child.__key__ + '.' + key, val, next

  set: (key, val, next) ->
    super key, val
    if key != '_id'
      log '[ Storing   ] ' + this.constructor.name + '.' + key if DEBUG
      Congo.set this, key, val, next

  ascend_set: (child, key, val, next) ->
    if child.__index__?
      log '[ Storing   ] ' + child.__key__ + '.' + child.__index__ + '.' + key if DEBUG
      Congo.set this, child.__key__ + '.' + child.__index__ + '.' + key, val, next
    else
      log '[ Storing   ] ' + child.__key__ + '.' + key if DEBUG
      Congo.set this, child.__key__ + '.' + key, val, next

  @load: (id, next) ->
    Congo.load this, id, next

class Congo
  @ObjectID:   ObjectID
  @Model:      Model
  @Collection: Collection

  @db: 'test'
  @connections: []

  # Close all open connections.  Use at your own risk.
  @terminate: ->
    for connection in @connections
      connection.close()
    @connections = []

  # Fish a connection out of the pool
  @fish: (next) ->
    for i in [0...@connections.length]
      connection = @connections[i]
      if connection.__available__
        log 'Connection: ' + i if DEBUG
        next connection
        return
    log 'Connection: ' + @connections.length if DEBUG
    connection = new mongodb.Db(@db, new mongodb.Server('localhost', 27017, { native_parser: true }))
    connection.__available__ = false
    connection.release = ->
      connection.__available__ = true
    @connections.push connection
    connection.open (err, connection) ->
      if err? then log err else next connection

  # Open a connection.  Pass in a Model class, instance or name and you'll get a collection, otherwise a connection.
  @open: (ref, next) ->
    @fish (connection) ->
      if ref instanceof Function and not next?
        ref connection
      else
        if ref instanceof Collection
          name = ref.constructor.name
        else if ref.prototype instanceof Collection
          name = ref.name
        else
          name = ref
        connection.createCollection name, (err, collection) ->
          collection.release = ->
            collection.db.release()
          if err? then log err else next collection

  @load: (model, id, next) ->
    @open model, (collection) ->
      collection.find { _id: id }, (err, cursor) ->
        log err if err?
        cursor.toArray (err, documents) ->
          log err if err?
          if documents.length > 0
            new model { _id: documents[0]._id }, (object) ->
              object.hydrate documents[0], ->
                next object
          else
            next null

  @create: (model, next) ->
    @open model, (collection) ->
      collection.insert model.__values__, (err, records) ->
        log err if err?
        model._id = records[0]._id
        collection.release()
        next model if next?

  @set: (model, key, val, next) ->
    @open model, (collection) ->
      doc = {}
      if val instanceof Model
        doc[key] = val.dehydrate()
      else
        doc[key] = val
      collection.update { _id: model._id }, { $set: doc }, { safe: true }, (err, doc) ->
        log err if err?
        collection.release()
        next() if next?

  @push: (model, key, val, next) ->
    @open model, (collection) ->
      doc = {}
      if val instanceof Model
        doc[key] = val.dehydrate()
      else
        doc[key] = val
      collection.update { _id: model._id }, { $push: doc }, { safe: true }, (err, doc) ->
        log err if err?
        collection.release()
        next() if next?

  @clear: (type, next) ->
    @open type, (collection) ->
      collection.remove {}, ->
        collection.release()
        next() if next?

  @use: (name) ->
    @db = name

for name, type of __type__
  Congo[name] = type

module.exports = Congo

