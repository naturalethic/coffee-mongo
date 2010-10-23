try
  util  = require 'util'
catch error
  util  = require 'sys'
log     = (args...) -> util.puts(a) for a in args
inspect = (args...) -> log(util.inspect(a, true, null)) for a in args
mongo   = require './mongo'

class CongoType
  constructor: (@number, @name) ->

__type__ =
  Double:   new CongoType 1,  'Double'
  String:   new CongoType 2,  'String'
  Identity: new CongoType 7,  'Identity'
  Date:     new CongoType 9,  'Date'
  Integer:  new CongoType 18, 'Integer'

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
  hydrate: (document) ->
    log '[ Hydrating ] ' + this.constructor.name if process.env.DEBUG?
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
    # Set values and hydrate subdocuments
    for key, type of @__types__
      type = type[0] if type instanceof Array
      if document[key]? and type instanceof Function and type.prototype instanceof Model
        if document[key] instanceof Array
          for val in document[key]
            new type (object) =>
              @relate key, object, @__values__[key].length
              @__values__[key].push object
              object.hydrate val
        else
          new type (object) =>
            log 'OBJECT'
            @relate key, object
            @__values__[key] = object
            object.hydrate document[key]
    @

  # Provide meta information regarding parent/child relationship
  relate: (key, val, index) ->
    if val instanceof Model
      if index?
        log '[ Relating  ] ' + @.constructor.name + '.' + key + '.' + index if process.env.DEBUG?
        val.__index__  = index
      else
        log '[ Relating  ] ' + @.constructor.name + '.' + key if process.env.DEBUG?
      val.__parent__ = this
      val.__key__    = key

  get: (key) ->
    @__values__[key]

  set: (key, val, next) ->
    log '[ Setting   ] ' + @constructor.name + '.' + key if process.env.DEBUG?
    @__values__[key] = val
    @relate key, val
    @ascend_set key, val, next

  # Signal up the parent chain to the collection to save the model
  ascend_set: (key, val, next) ->
    log '[ Ascending ] ' + key if process.env.DEBUG?
    if @__parent__
      if @__index__?
        @__parent__.ascend_set @__key__ + '.' + @__index__ + '.' + key, val, next
      else
        @__parent__.ascend_set @__key__ + '.' + key, val, next
    else
      next() if next?

  push: (key, val, next) ->
    @relate key, val, this[key].length
    this[key].push val
    @ascend_push key, val, next

  ascend_push: (key, val, next) ->
    log '[ Ascending ] ' + key if process.env.DEBUG?
    if @__parent__
      if @__index__?
        @__parent__.ascend_push @__key__ + '.' + @__index__ + '.' + key, val, next
      else
        @__parent__.ascend_push @__key__ + '.' + key, val, next
    else
      next() if next?

class Collection extends Model
  _id: __type__.Identity

  @extended: (subclass) ->
    subclass.load  = Collection.load
    subclass.clear = Collection.clear

  constructor: (initial, next) ->
    if initial instanceof Function
      next = initial
      initial = null
    super initial
    if not @__values__._id?
      Congo.db.insert @constructor.name, @__values__, =>
        next @
    else if next?
      next @

  ascend_push: (key, val, next) ->
    @store_push key, val, next

  store_push: (key, val, next) ->
    log '[ Storing   ] ' + @constructor.name + '.' + key if process.env.DEBUG?
    doc = {}
    if val instanceof Model
      doc[key] = val.dehydrate()
    else
      doc[key] = val
    Congo.db.update @constructor.name, { _id: @__values__._id }, { $push: doc }, next

  ascend_set: (key, val, next) ->
    @store_set key, val, next

  store_set: (key, val, next) ->
    return if key == '_id'
    log '[ Storing   ] ' + @constructor.name + '.' + key if process.env.DEBUG?
    doc = {}
    if val instanceof Model
      doc[key] = val.dehydrate()
    else
      doc[key] = val
    Congo.db.update @constructor.name, { _id: @__values__._id }, { $set: doc }, next

  save: (next) ->
    Congo.db.update @constructor.name, { _id: @__values__._id }, @dehydrate(), next

  @load: (id, next) ->
    id = new mongo.ObjectID(id) if typeof id == 'string'
    Congo.db.query @name, { _id: id }, (documents) =>
      if documents.length == 0
        next null if next?
      else
        next ((new @ { _id: documents[0]._id }).hydrate documents[0]) if next?

  @clear: (next) ->
    Congo.db.remove @name, {}, next

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

