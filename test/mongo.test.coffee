try
  util  = require 'util'
catch error
  util  = require 'sys'
log     = (args...) -> util.puts(a) for a in args
inspect = (args...) -> log(util.inspect(a, true, null)) for a in args
assert  = require 'assert'
congo   = require '../lib/congo'

class Provider extends congo.Model
  name:    congo.String
  account: congo.String

class Shipping extends congo.Model
  providers: [ Provider ]
  platforms: [ congo.String ]

class Address extends congo.Model
  street:   congo.String
  city:     congo.String
  shipping: [ Shipping ]

class Person extends congo.Model
  name:      congo.String
  addresses: [ Address ]

class Account extends congo.Collection
  people: [ Person ]

congo.use 'test'

test_result = JSON.parse '{"people":[{"name":"Andrew Jackson","addresses":[{"street":"123 Round Way","city":"Seattle","shipping":[{"providers":[{"name":"UPS","account":"UPS123"},{"name":"FedEx","account":"FED123"}],"platforms":[]}]},{"street":"456 Round Way","city":"Portland","shipping":[{"providers":[{"name":"UPS","account":"UPS456"},{"name":"FedEx","account":"FED456"}],"platforms":[]}]}]}],"_id":"4cb6e71128827b5c0f000001"}'

store_address_0 = (person, next) ->
  new Address { street: '123 Round Way', city: 'Seattle' }, (address) ->
    person.addresses.push address, ->
      new Shipping {}, (shipping) ->
        address.shipping.push shipping, ->
          new Provider { name: 'UPS', account: 'UPS123' }, (provider) ->
            shipping.providers.push provider, ->
              new Provider { name: 'FedEx', account: 'FED123' }, (provider) ->
                shipping.providers.push provider, next

store_address_1 = (person, next) ->
  new Address { street: '456 Round Way', city: 'Portland' }, (address) ->
    person.addresses.push address, ->
      new Shipping {}, (shipping) ->
        address.shipping.push shipping, ->
          new Provider { name: 'UPS', account: 'UPS456' }, (provider) ->
            shipping.providers.push provider, ->
              new Provider { name: 'FedEx', account: 'FED456' }, (provider) ->
                shipping.providers.push provider, next

Account.clear ->
  new Account {}, (account) ->
    new Person { name: 'Andrew Jackson' }, (person) ->
      account.people.push person, ->
        store_address_0 person, ->
          store_address_1 person, ->
            Account.load account._id, (account) ->
              log '--- Setting properties on a complexish tree using scalars, objects, and arrays [sequential]'
              result = account.__dehydrate__()
              result._id = test_result._id
              assert.deepEqual(test_result, result)

  new Account {}, (account) ->
    new Person { name: 'Andrew Jackson' }, (person) ->
      account.people.push person, ->
        store_address_0 person
        store_address_1 person
        go = ->
          Account.load account._id, (account) ->
            log '--- Setting properties on a complexish tree using scalars, objects, and arrays [asynchronous] '
            result = account.__dehydrate__()
            result._id = test_result._id
            assert.deepEqual(test_result, result)
        setTimeout go, 400

  new Account {}, (account) ->
    new Person { name: 'Andrew Jackson' }, (person) ->
      account.people.push person, ->
        store_address_0 person, ->
          Account.load account._id, (loaded_account) ->
            log '--- Check that a loaded and hydrated document matches the saved document'
            assert.deepEqual(account.__dehydrate__(), loaded_account.__dehydrate__())

  new Account {}, (account) ->
    new Person { name: 'Andrew Jackson' }, (person) ->
      account.people.push person, ->
        store_address_0 person, ->
          person.name = 'Thomas Jefferson'
          person.addresses[0].city = 'Portland'
          person.addresses[0].shipping[0].providers[1].account = 'FED789'
        go1 = ->
          new Provider { name: 'FedEx', account: 'FEDXXX' }, (provider) ->
            person.addresses[0].shipping[0].providers[1] = provider
          setTimeout go2, 400
        go2 = ->
          Account.load account._id, (loaded_account) ->
            log '--- Setting scalars via assignment'
            assert.deepEqual(account.__dehydrate__(), loaded_account.__dehydrate__())
        setTimeout go2, 400

  new Account {}, (account) ->
    new Person { name: 'Andrew Jackson' }, (person) ->
      account.people.push person, ->
        store_address_0 person, ->
    go = ->
      Account.load account._id, (loaded1) ->
        loaded1.people[0].name = 'Thomas Jefferson'
        new Provider { name: 'FedEx', account: 'FEDXXX' }, (provider) ->
          loaded1.people[0].addresses[0].shipping[0].providers[1] = provider
        go2 = ->
          Account.load account._id, (loaded2) ->
            log '--- Setting properties after hydration'
            assert.deepEqual(loaded1.__dehydrate__(), loaded2.__dehydrate__())
        setTimeout go2, 400
    setTimeout go, 400
