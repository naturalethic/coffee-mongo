parseRQL = require('../../rql/lib/parser').parseGently
Query = require('../../rql/lib/query').Query
parseQuery = (query) ->
	query = parseRQL(query).normalize()
	console.log 'RQL', query
	query.search

# valid funcs
valid_funcs = ['lt','lte','gt','gte','ne','in','nin','not','mod','all','size','exists','type','elemMatch']
# funcs which definitely require array arguments
requires_array = ['in','nin','all','mod']
# funcs acting as operators
valid_operators = ['or', 'and', 'not'] #, 'xor']

parse = (query) ->

	options = {}
	search = {}

	walk = (name, terms) ->
		search = {} # compiled search conditions
		# iterate over terms
		(terms or []).forEach (term) ->
			term ?= {}
			func = term.name
			args = term.args
			# ignore bad terms
			# N.B. this filters quirky terms such as for ?or(1,2) -- term here is a plain value
			return if not func or not args
			# http://www.mongodb.org/display/DOCS/Querying
			#console.log 'TERM', func, args
			# nested terms? -> recurse
			#if args[0] and typeof args[0] is 'object'
			if args[0] instanceof Query
				if 0 <= valid_operators.indexOf func
					#console.log 'WALK', func, args
					search['$'+func] = walk func, args
					#console.log 'WALKED', search['$'+func]
				# N.B. here we encountered a custom function
				# ...
			# http://www.mongodb.org/display/DOCS/Advanced+Queries
			# structured query syntax
			else
				if func is 'le'
					func = 'lte'
				else if func is 'ge'
					func = 'gte'
				# args[0] is the name of the property
				key = args.shift()
				key = key.join('.') if key instanceof Array
				# id --> _id
				key = '_id' if key is 'id'
				# the rest args are parameters to func()
				if 0 <= requires_array.indexOf func
					#console.log 'ARR', func, args
					args = args[0]
				# match on regexp means equality
				else if func is 'match'
					func = 'eq'
					regex = new RegExp()
					regex.compile.apply(regex, args)
					args = regex
				else
					# FIXME: do we really need to .join()?!
					args = if args.length is 1 then args[0] else args.join()
				# regexp inequality means negation of equality
				func = 'not' if func is 'ne' and args instanceof RegExp
				# valid functions are prepended with $
				func = '$'+func if 0 <= valid_funcs.indexOf func
				# $or requires an array of conditions
				if name is 'or'
					search = [] unless search instanceof Array
					x = {}
					x[if func is 'eq' then key else func] = args
					search.push x
				# other functions pack conditions into object
				else
					#console.log 'KEY', key, args, func, name
					# several conditions on the same property are merged into the single object condition
					search[key] = {} if search[key] is undefined
					search[key][func] = args if search[key] instanceof Object and search[key] not instanceof Array
					# equality cancels all other conditions
					if func is 'eq'
						search[key] = args
						# N.B. exact condition on id is special -- we can reduce search for use in findOne()!
						if key is '_id'
							# FIXME: id must be string?
							options.id = search[key] = args #String args
		# TODO: add support for query expressions as Javascript
		# TODO: add support for server-side functions
		#console.log 'SEA', search
		search

	query = parseRQL(query).normalize()
	search = walk query.search.name, query.search.args
	options.sort = query.sortObj if query.sortObj
	options.fields = query.selectObj if query.selectObj
	if query.limit
		options.limit = query.limit[0] 
		options.skip = query.limit[1] 
	#console.log meta: options, search: search, terms: query
	meta: options, search: search, terms: query

module.exports.parse = parse
