coffee-mongo
============

Experiment to write a Mongo driver in CoffeeScript on Node.

Possible further experiments for the intrepid
---------------------------------------------
* connection pooling (rudimentary support already built)
* full async support on all blocking operations
* full support for the Mongo query api
* support for all Mongo data types
* models as CoffeeScript classes and/or Javascript objects
* automatic references between collections (joining)
* custom object id factories (done)

---

Example
-------

    # CoffeeScript
    db = new mongo.Database 'test'
    db.insert 'Country', { name: 'Iceland', population: 316252 }, (error, document) ->
      db.remove 'Country', { _id: document._id }, (error) ->
        ...

    # Javascript
    db = new mongo.Database('test');
    db.insert('Country', { name: 'Iceland', population: 316252 }, function (error, document) {
      db.remove('Country', { _id: document._id }, function (error) {
        ...
      })
    });

---

