Congo
=====

Modeling library for use with [Node](http://nodejs.org/), [CoffeeScript](http://jashkenas.github.com/coffee-script/), and [Mongo](http://www.mongodb.org/).

---

Features
--------

* connection pooling
* models as CoffeeScript classes
* asynchronous live updating of your Mongo documents using standard assignment on your models
* deep tree assignment
* array push support
* loading documents into models (hydration)
* dehydration into standard object trees
* full async support on all operations

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

    congo.Identity
    congo.String
    congo.Date
    congo.Integer
    congo.Double

**Functions**

    congo.use(name)            # set the database to use
    congo.terminate()          # close all open connections -- use only if you *know* your app is finished with them

**congo.Model (class)**

    constructor(next)
    constructor(initial, next) # initial is an object with initial values, object is created in collection
    dehydrate()                # return a plain object tree
    hydrate(document)          # populate a model with the values in document, recursing down the tree instantiating the appropriate models
    get(key)                   # return a value on the model
    set(key, val, next)        # set a value on the model, calling next after it has updated the store
    push(key, val, next)       # push a value into an array on the model

**congo.Collection (class)**

Subclass of Model (methods are static)

    load(id, next)             # load an object from the collection given an ObjectID, passes the hydrated object to next
    clear(next)                # remove all documents from this collection

---

Notes
-----

* Congo borrows the pure bson library provided by [node-mongodb-native](http://github.com/christkv/node-mongodb-native).  If you prefer the
  compiled native version, go ahead and compile it and replace ``lib/vendor/bson.js`` with ``bson.node``.  Many thanks and all credit goes to
  Christian Amor Kvalheim <christkv@gmail.com> for his work on that.
* If you have questions or comments, I often frequent ``#coffeescript`` on freenode.
