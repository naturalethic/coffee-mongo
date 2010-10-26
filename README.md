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

* support for more first class array operations
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
      name:      congo.String { default: 'Anonymous' }
      addresses: [ Address ]

    class Account extends congo.Collection
      people: [ Person ]

**Creating/Updating**

    store_address = (person, next) ->
      new Address { street: '123 Round Way', city: 'Seattle' }, (address) ->
        person.addresses.push address, ->
          new Shipping {}, (shipping) ->
            address.shipping.push shipping, ->
              new Provider { name: 'UPS', account: 'UPS123' }, (provider) ->
                shipping.providers.push provider, ->
                  new Provider { name: 'FedEx', account: 'FED123' }, (provider) ->
                    shipping.providers.push provider, next

    new Account (account) ->
      new Person { name: 'Andrew Jackson' }, (person) ->
        account.people.push person, ->
          store_address person, ->
            person.name = 'Thomas Jefferson'
            person.name = 'Thomas Jefferson'
            person.addresses[0].city = 'Portland'
            person.addresses[0].shipping[0].providers[0].account = 'UPS789'
            new Provider { name: 'FedEx', account: 'FEDXXX' }, (provider) ->
              person.addresses[0].shipping[0].providers[1] = provider

**Loading**

    Account.load '4cb7386cf91998d110000001', (account) ->
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

**congo.ArrayType (class)**

Arrays in the model are actually instances of this class.

    push(val, next)            # push a new value onto the array and call next after it has been saved to the store
    __set__(index, val, next)  # set a value on the array, calling next after it has updated the store (only set on indexes that have been pushed)
    __get__(index)             # return a value on the array
    __dehydrate__()            # return a plain object tree
    __hydrate__(array)         # populate with the values in array, recursing down the tree instantiating the appropriate models

**congo.Model (class)**

    constructor(next)
    constructor(initial, next) # initial is an object with initial values, object is created in collection
    __dehydrate__()            # return a plain object tree
    __hydrate__(document)      # populate a model with the values in document, recursing down the tree instantiating the appropriate models
    __get__(key)               # return a value on the model
    __set__(key, val, next)    # set a value on the model, calling next after it has updated the store

**congo.Collection (class)**

Subclass of Model (methods are static)

    load(id, next)             # load an object from the collection given an ObjectID, passes the hydrated object to next
    remove(selector)           # remove documents matching the selector
    clear(next)                # remove all documents from this collection

---

Notes
-----

* Congo borrows the pure bson library provided by [node-mongodb-native](http://github.com/christkv/node-mongodb-native).  If you prefer the
  compiled native version, go ahead and compile it and replace ``lib/vendor/bson.js`` with ``bson.node``.  Many thanks and all credit goes to
  [Christian Amor Kvalheim](mailto:christkv@gmail.com) for his work on that.
* If you have questions or comments, I often frequent ``#coffeescript`` on freenode.
