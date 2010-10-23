try
  util  = require 'util'
catch error
  util  = require 'sys'
log     = (args...) -> util.puts(a) for a in args
inspect = (args...) -> log(util.inspect(a)) for a in args
_       = require '../lib/vendor/underscore'
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
    person.push 'addresses', address, ->
      new Shipping {}, (shipping) ->
        address.push 'shipping', shipping, ->
          new Provider { name: 'UPS', account: 'UPS123' }, (provider) ->
            shipping.push 'providers', provider, ->
              new Provider { name: 'FedEx', account: 'FED123' }, (provider) ->
                shipping.push 'providers', provider, next

store_address_1 = (person, next) ->
  new Address { street: '456 Round Way', city: 'Portland' }, (address) ->
    person.push 'addresses', address, ->
      new Shipping {}, (shipping) ->
        address.push 'shipping', shipping, ->
          new Provider { name: 'UPS', account: 'UPS456' }, (provider) ->
            shipping.push 'providers', provider, ->
              new Provider { name: 'FedEx', account: 'FED456' }, (provider) ->
                shipping.push 'providers', provider, next

Account.clear ->
  new Account {}, (account) ->
    new Person { name: 'Andrew Jackson' }, (person) ->
      account.push 'people', person, ->
        store_address_0 person, ->
          store_address_1 person, ->
            Account.load account._id, (account) ->
              log '--- Setting properties on a complexish tree using scalars, objects, and arrays [sequential]'
              result = account.dehydrate()
              result._id = test_result._id
              assert.ok _.isEqual(test_result, result)

  new Account {}, (account) ->
    new Person { name: 'Andrew Jackson' }, (person) ->
      account.push 'people', person, ->
        store_address_0 person
        store_address_1 person
        go = ->
          Account.load account._id, (account) ->
            log '--- Setting properties on a complexish tree using scalars, objects, and arrays [asynchronous] '
            result = account.dehydrate()
            result._id = test_result._id
            assert.ok _.isEqual(test_result, result)
        setTimeout go, 200

  new Account {}, (account) ->
    new Person { name: 'Andrew Jackson' }, (person) ->
      account.push 'people', person, ->
        store_address_0 person, ->
          Account.load account._id, (loaded_account) ->
            log '--- Check that a loaded and hydrated document matches the saved document'
            assert.ok _.isEqual(account.dehydrate(), loaded_account.dehydrate())

  new Account {}, (account) ->
    new Person { name: 'Andrew Jackson' }, (person) ->
      account.push 'people', person, ->
        store_address_0 person, ->
          person.name = 'Thomas Jefferson'
          person.addresses[0].city = 'Portland'
          person.addresses[0].shipping[0].providers[1].account = 'FED789'
        go = ->
          Account.load account._id, (loaded_account) ->
            log '--- Setting scalars via assignment'
            assert.ok _.isEqual(account.dehydrate(), loaded_account.dehydrate())
        setTimeout go, 200
