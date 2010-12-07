coffee-mongo
============

Modeling library for use with [Node](http://nodejs.org/), [CoffeeScript](http://jashkenas.github.com/coffee-script/), and [Mongo](http://www.mongodb.org/).

*This library can be compiled to Javascript for deployment without a dependency on CoffeeScript*

*Requires 0.3.x branch of Node.js*


Goal
----

This library aims to be a comprehensive all-in-one solution for interacting with MongoDB from Node.  

Status
------

Whereas initially the library depended on a few external drivers and focused on modeling, it has been reset to build a full
package from the ground up.  Modeling has been removed and pushed out while a tight, clean low-level interface is developed.

Planned Features
----------------

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

Notes
-----

* If you have questions or comments, I often frequent ``#coffeescript`` on freenode.
