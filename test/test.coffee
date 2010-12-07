promises = require './support/promised-io/lib/promise'
global.defer = promises.defer
global.wait = (promise, callback, errback) -> promises.when promise, callback, errback or callback
Database = require('./support/coffee-mongo/lib/mongo').Database
ObjectID = require('./support/coffee-mongo/lib/mongo').ObjectID

#
# object creation helpers
#
Object.apply = (o, props) ->
	x = Object.create o
	for k, v of props
		prop = if v?.value then v else value: v
		Object.defineProperty x, k, prop
	x

# shallow copy
Object.clone = (o) ->
	n = Object.create Object.getPrototypeOf o
	props = Object.getOwnPropertyNames o
	for pName in props
		Object.defineProperty n, pName, Object.getOwnPropertyDescriptor(o, pName)
	n

# kick off properties mentioned in fields from object o
Object.veto = (o, fields) ->
	for k in fields
		if typeof k is 'string'
			delete o[k]
		else if k instanceof Array
			k1 = k.shift()
			v1 = o[k1]
			if v1 instanceof Array
				o[k1] = v1.map (x) -> veto(x, if k.length > 1 then [k] else k)
			else if v1
				o[k1] = veto(v1, if k.length > 1 then [k] else k)
	o
	#Object.freeze o

#
# improve console.log
#
sys = require 'util'
inspect = require('./support/eyes.js/lib/eyes.js').inspector()
console.log = () ->
	for arg in arguments
		sys.debug inspect arg

#
# async helper
#
global.Step = (context, steps) ->
	# define the main callback
	next = () ->
		# return if there are no steps left
		return arguments[0] unless steps.length
		# get the next step to execute
		fn = steps.shift()
		# run the step in a try..catch block so exceptions don't get out of hand
		try
			result = fn.apply context, arguments
			result = wait result, next, next unless result is undefined
		catch err
			# pass any exceptions on through the next callback
			next err
		result
	next()

#
# Store
#
class Store extends Database
	constructor: (@collection, @options) ->
		@options ?= {}
		@options.host ?= 'localhost'
		#@options.host.replace /^mongodb:\/\/([^\/]+)/ # TODO
		@host = @options.host
		@port = @options.port or 27017
		@name = @options.name or 'test'
		@idfactory = (collection, next) -> next null, (new ObjectID).toHex()
		@connections = []
	insert: (document) ->
		deferred = defer()
		super @collection, document, (err, res) ->
			deferred.reject err if err
			res.id = res._id
			delete res._id
			deferred.resolve res
		deferred.promise
	update: (changes, query) ->
		query ?= {}
		query.$atomic = 1
		deferred = defer()
		super @collection, query, {$set: changes}, (err, res) ->
			if err then deferred.reject err else deferred.resolve res
		deferred.promise
	save: (document) ->
		if not document._id
			@insert document
		else
			@update document, {_id: document._id}
	find: (query) ->
		deferred = defer()
		super @collection, query, (err, res) ->
			if err then deferred.reject err else deferred.resolve res
		deferred.promise
	find_one: (query) ->
		deferred = defer()
		super @collection, query, (err, res) ->
			if err then deferred.reject err else deferred.resolve res
		deferred.promise
	clear: () -> throw ReferenceError() # way dangerous
	remove: (query) ->
		deferred = defer()
		super @collection, query, (err, res) ->
			if err then deferred.reject err else deferred.resolve res
		deferred.promise
	create: (properties) ->
		properties
	create: (properties) ->
		properties

class Document
	constructor: (properties) ->
		Object.apply null, properties
	save: () ->
		# where to get the collection?!
		store.save()

db = new Store 'Hit', {name: 'omega'}


console.log 'START'
context = {}
Step context, [
	() ->
		true
		#db.remove()
	() ->
		console.log 'INSERTING'
		db.insert { name: 'Russia', date: Date() }
	(res) ->
		console.log 'INSERTED', res
		console.log 'UPDATING'
		db.update { name: 'Russia!' }
	(res) ->
		console.log 'UPDATED', res
		db.find {}
	(res) ->
		console.log 'DONE', res.length
		process.exit 0
]
