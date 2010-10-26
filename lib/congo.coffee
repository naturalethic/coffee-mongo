try
  util  = require 'util'
catch error
  util  = require 'sys'
log     = (args...) -> util.puts(a) for a in args
inspect = (args...) -> log(util.inspect(a, true, null)) for a in args
mongo   = require './mongo'

class Type
  constructor: (options) ->
    if @ instanceof Function
      return new arguments.callee.caller options
    else
      @options = if options? then options else {}

  initialize: (val) ->
    return val if val?
    return @options['default'] if @options['default']?
    null

class ArrayType
  constructor: (@__type__, @__parent__, @__key__) ->
    @__values__ = []
    @__defineGetter__ 'length', =>
      @__values__.length

  push: (val, next) ->
    log '[ Pushing   ] ' + @__key__ if process.env.DEBUG?
    index = @__values__.length
    @__defineSetter__ index, (val) =>
      @__set__ index, val
    @__defineGetter__ index, =>
      @__get__ index
    @__values__[index] = val
    @__relate__ val, index
    @__parent__.__ascend_push__ @__key__, val, next

  __ascend_push__: (key, val, next) ->
    log '[ Ascending ] ' + @__key__ + '.' + key if process.env.DEBUG?
    @__parent__.__ascend_push__ @__key__ + '.' + key, val, next

  # pop: ->
  #   delete @[@__values__.length - 1]
  #   @__values__.pop()

  # unshift: (val) ->
  #   index = @__values__.length
  #   @__values__.unshift val
  #   @__defineSetter__ index, (val) =>
  #     @__values__[index] = val
  #   @__defineGetter__ index, =>
  #     @__values__[index]

  # shift: ->
  #   delete @[@__values__.length - 1]
  #   @__values__.shift()

  __set__: (index, val, next) ->
    log '[ Setting   ] ' + @__key__ + '.' + index if process.env.DEBUG?
    @__values__[index] = val
    @__relate__ val, index
    @__parent__.__ascend_set__ @__key__ + '.' + index, val, next

  __ascend_set__: (key, val, next) ->
    log '[ Ascending ] ' + @__key__ + '.' + key if process.env.DEBUG?
    @__parent__.__ascend_set__ @__key__ + '.' + key, val, next

  __get__: (index) ->
    @__values__[index]

  __relate__: (val, index) ->
    if val instanceof Model
      log '[ Relating  ] ' + @__key__ + '.' + index if process.env.DEBUG?
      val.__index__  = index
      val.__parent__ = @
      val.__key__    = @__key__

  __dehydrate__: ->
    array = []
    for item in @__values__
      if item instanceof Model
        array.push item.__dehydrate__()
      else
        array.push item
    array

  __hydrate__: (array) ->
    log '[ Hydrating ] ' + @__key__ if process.env.DEBUG?
    for item in array
      index = @__values__.length
      if @__type__.prototype instanceof Model
        new @__type__ (object) =>
          object.__hydrate__ item
          @__relate__ object, index
          @__values__.push object
      else
        @__values__.push item
      @__defineSetter__ index, (val) =>
        @__set__ index, val
      @__defineGetter__ index, =>
        @__get__ index

class DateType extends Type
  initialize: (val) ->
    return val if val?
    return @options['default'] if @options['default']?
    new Date()

__type__ =
  Identity: (args...) -> new Type args...
  Integer:  (args...) -> new Type args...
  Double:   (args...) -> new Type args...
  String:   (args...) -> new Type args...
  Date:     (args...) -> new DateType args...

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
    for all key, type of @
      continue if key == 'constructor' or (key[0] == '_' and key[1] == '_')
      type = type() if type instanceof Function and not (type.prototype instanceof Model)
      type[0] = type[0]() if type instanceof Array and type[0] instanceof Function and not (type[0].prototype instanceof Model)
      if (( type instanceof Type or type.prototype instanceof Model ) or
          ( type instanceof Array and ( type[0] instanceof Type or type[0].prototype instanceof Model )))
        @__types__[key] = type
        @__values__[key] = null
        @__values__[key] = (type.initialize initial[key]) if type instanceof Type
        if type instanceof Array
          @__values__[key] = new ArrayType type[0], @, key
        ((key) =>
          @__defineGetter__ key, =>
            @__get__ key
          @__defineSetter__ key, (val) =>
            @__set__ key, val)(key)
    next this if next?

  # Return an object tree minus all the meta information
  __dehydrate__: ->
    document = {}
    for key, type of @__types__
      if type instanceof Array
        document[key] = @__values__[key].__dehydrate__()
      else if @__values__[key] instanceof Model
        document[key] = @__values__[key].__dehydrate__()
      else
        document[key] = @__values__[key]
    document

  # Populate this object with the passed document
  __hydrate__: (document) ->
    log '[ Hydrating ] ' + @constructor.name if process.env.DEBUG?
    for key, type of @__types__
      if type instanceof Array
        @__values__[key] = new ArrayType type[0], @, key
        @__values__[key].__hydrate__ document[key]
      else if type instanceof Function and type.prototype instanceof Model
        new type (object) =>
          @__relate__ key, object
          @__values__[key] = object
          object.__hydrate__ document[key]
      else
        @__values__[key] = document[key]
    @

  # Provide meta information regarding parent/child relationship
  __relate__: (key, val, index) ->
    if val instanceof Model
      if index?
        log '[ Relating  ] ' + @.constructor.name + '.' + key + '.' + index if process.env.DEBUG?
        val.__index__  = index
      else
        log '[ Relating  ] ' + @.constructor.name + '.' + key if process.env.DEBUG?
      val.__parent__ = @
      val.__key__    = key

  __get__: (key) ->
    @__values__[key]

  __set__: (key, val, next) ->
    log '[ Setting   ] ' + @constructor.name + '.' + key if process.env.DEBUG?
    @__values__[key] = val
    @__relate__ key, val
    @__ascend_set__ key, val, next

  # Signal up the parent chain to the collection to save the model
  __ascend_set__: (key, val, next) ->
    log '[ Ascending ] ' + key if process.env.DEBUG?
    if @__parent__
      if @__index__?
        @__parent__.__ascend_set__ @__index__ + '.' + key, val, next
      else
        @__parent__.__ascend_set__ @__key__ + '.' + key, val, next
    else
      next() if next?

  __ascend_push__: (key, val, next) ->
    if @__parent__
      if @__index__?
        @__parent__.__ascend_push__ @__index__ + '.' + key, val, next
      else
        @__parent__.__ascend_push__ @__key__ + '.' + key, val, next
    else
      next() if next?

class Collection extends Model
  _id: __type__.Identity

  constructor: (initial, next) ->
    @__flushing__ = false
    @__store_queue__ = []
    if initial instanceof Function
      next = initial
      initial = null
    super initial
    if not @__values__._id?
      document = @__dehydrate__()
      @__queue_store__ (qnext) =>
        log '[ Creating  ] ' + @constructor.name if process.env.DEBUG?
        Congo.db.insert @constructor.name, document, (id) =>
          # log 'ID: ' + id
          @__values__._id = id
          next @ if next?
          qnext()
    else if next?
      next @

  __ascend_push__: (key, val, next) ->
    document = {}
    if val instanceof Model
      document[key] = val.__dehydrate__()
    else
      document[key] = val
    @__queue_store__ (qnext) =>
      log '[ Storing   ] ' + @constructor.name + '.' + key if process.env.DEBUG?
      Congo.db.update @constructor.name, { _id: @__values__._id }, { $push: document }, ->
        next() if next?
        qnext()

  __ascend_set__: (key, val, next) ->
    return if key == '_id'
    document = {}
    if val instanceof Model
      document[key] = val.__dehydrate__()
    else
      document[key] = val
    @__queue_store__ (qnext) =>
      log '[ Storing   ] ' + @constructor.name + '.' + key if process.env.DEBUG?
      Congo.db.update @constructor.name, { _id: @__values__._id }, { $set: document }, ->
        next() if next?
        qnext()

  __queue_store__: (op) ->
    @__store_queue__.push op
    if not @__flushing__
      @__flushing__ = true
      @__flush_store_queue__()

  __flush_store_queue__: ->
    if @__store_queue__.length == 0
      @__flushing__ = false
    else
      @__store_queue__.shift()(=>
        @__flush_store_queue__())

  __save__: (next) ->
    Congo.db.update @constructor.name, { _id: @__values__._id }, @__dehydrate__(), next

  @load: (id, next) ->
    id = new mongo.ObjectID(id) if typeof id == 'string'
    Congo.db.query @name, { _id: id }, (documents) =>
      if documents.length == 0
        next null if next?
      else
        next ((new @ { _id: documents[0]._id }).__hydrate__ documents[0]) if next?

  @remove: (selector, next) ->
    Congo.db.remove @name, selector, next

  @clear: (next) ->
    @remove {}, next

  @extended: (subclass) ->
    subclass.load   = Collection.load
    subclass.remove = Collection.remove
    subclass.clear  = Collection.clear

class Congo
  @ObjectID:   mongo.ObjectID
  @Model:      Model
  @Collection: Collection

  @use: (name) ->
    @db = new mongo.Database name

  @terminate: ->
    @db.close()

for name, type of __type__
  Congo[name] = type

module.exports = Congo

