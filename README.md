Congo
=====

Modeling library for use with [Node](http://nodejs.org/), [CoffeeScript](http://jashkenas.github.com/coffee-script/), and [Mongo](http://www.mongodb.org/).

---

Dependencies
------------

* [node-mongodb-native](http://github.com/christkv/node-mongodb-native)

Features
--------

* connection pooling
* models as CoffeeScript classes
* asynchronous live updating of your Mongo documents using standard assignment on your models
* deep tree assignment
* array push support using the CongoObject api
* loading documents into models (hydration)
* hehydration into standard object trees
* full async support on all operations through the CongoObject api

Planned
-------

* support for all first class array operations
* sub-document loading/updating
* full support for the Mongo query api returning hydrated objects
* support for all Mongo data types

---

Examples
--------

**Defining**

    class Provider extends congo.Object
      name:    congo.String
      account: congo.String

    class Shipping extends congo.Object
      providers: [ Provider ]
      platforms: [ congo.String ]

    class Address extends congo.Object
      street:   congo.String
      city:     congo.String
      shipping: [ Shipping ]

    class Person extends congo.Object
      name:      congo.String
      addresses: [ Address ]

    class Account extends congo.Collection
      people: [ Person ]

**Creating/Updating**

    store_address = (person, next) ->
      new Address { street: '123 Round Way', city: 'Seattle' }, (address) ->
        person.push 'addresses', address, ->
          new Shipping {}, (shipping) ->
            address.push 'shipping', shipping, ->
              new Provider { name: 'UPS', account: 'UPS123' }, (provider) ->
                shipping.push 'providers', provider, ->
                  new Provider { name: 'FedEx', account: 'FED123' }, (provider) ->
                    shipping.push 'providers', provider, next

    new Account {}, (account) ->
      new Person { name: 'Andrew Jackson' }, (person) ->
        account.push 'people', person, ->
          store_address person, ->
            person.name = 'Thomas Jefferson'
            person.addresses[0].city = 'Portland'
            person.addresses[0].shipping[0].providers[1].account = 'FED789'

**Loading**

    Account.load new congo.ObjectID('4cb7386cf91998d110000001'), (account) ->
      # do something with account

---

API
---

    congo = require './path/to/congo'

**ObjectID**

    congo.ObjectID             # Constructor for mongo object identifier

**Types**

    congo.String
    congo.Identity
    congo.Date
    congo.Integer

**Functions**

    congo.use(name)            # set the database to use
    congo.terminate()          # close all open connections -- use only if you *know* your app is finished with them

**congo.Model (class)**

    constructor(next)
    constructor(initial, next) # initial is an object with initial values, object is created in collection
    dehydrate()                # return a plain object tree
    hydrate(document, next)    # populate a model with the values in document, recursing down the tree instantiating the appropriate models
    get(key)                   # return a value on the model
    set(key, val, next)        # set a value on the model, calling next after it has updated the store
    push(key, val, next)       # push a value into an array on the model

**congo.Collection (class)**

Subclass of Model (methods are static)

    load(id, next)             # load an object from the collection given an ObjectID, passes the hydrated object to next
    clear(next)                # remove all documents from this collection
