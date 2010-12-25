runner.settle ->
  @db.close()
  @next()

runner.mettle ->
  @db = new mongo.Database 'test'
  @db.drop 'Country', =>
    @db.drop 'Pet', =>
      @db.drop 'fm', =>
        @db.drop 'Food', =>
          @db.drop 'Hex', =>
            @db.drop 'Planet', =>
              @next()

runner.mettle ->
  @tell 'hex ids'
  db = new mongo.Database 'test', { hex: true }
  db.insert 'Hex', { foo: 'bar' }, (error, document) =>
    assert.equal typeof document._id, 'string'
    assert.equal document._id.length, 24
    db.close()
    @next()

runner.mettle ->
  @tell 'insert with given id'
  @iceland = { _id: 1, name: 'Iceland', population: 316252 }
  @db.insert 'Country', @iceland, (error, document) =>
    assert.equal error, null
    assert.deepEqual @iceland, document
    @next()

runner.mettle ->
  @tell 'find by query'
  @db.find 'Country', { _id: 1 }, (error, documents) =>
    assert.equal error, null
    assert.equal documents.length, 1
    assert.deepEqual @iceland, documents[0]
    @db.find 'Country', { name: /ce/ }, (error, documents) =>
      assert.equal error, null
      assert.equal documents.length, 1
      assert.deepEqual @iceland, documents[0]
      @next()

runner.mettle ->
  @tell 'find with limit/skip'
  i = 100
  insert = =>
    @db.insert 'Food', { name: 'Apple', type: 'Fruit', number: i }, =>
      if --i
        insert()
      else
        @db.find 'Food', { }, { limit: 10 }, (error, foods) =>
          assert.equal foods.length, 10
          @db.find_one 'Food', { }, { skip: 10, sort: { number: -1 } }, (error, food) =>
            assert.equal food.number, 90
            @next()
  insert()

# runner.mettle ->
#   @tell 'find with limit/skip'
#   for i in [1..100]
#     @db.queue 'insert', 'Food', { name: 'Apple', type: 'Fruit', number: i }
#   @db.flush()
#   @db.on 'flush', =>
#     @db.find 'Food', { }, { limit: 10 }, (error, foods) =>
#       assert.equal foods.length, 10
#       @db.find_one 'Food', { }, { skip: 10 }, (error, food) =>
#         assert.equal food.number, 90
#         @next()

runner.mettle ->
  @tell 'find with fields'
  @db.find_one 'Food', { }, { fields: [ 'name' ] }, (error, food) =>
    delete food._id
    assert.deepEqual food, { name: 'Apple' }
    @db.find_one 'Food', { }, { fields: { name: 1} }, (error, food) =>
      delete food._id
      assert.deepEqual food, { name: 'Apple' }
      @next()

runner.mettle ->
  @tell 'find with sort'
  @db.find_one 'Food', { }, { sort: { number: 1 } }, (error, food) =>
    assert.equal food.number, 1
    @db.find_one 'Food', { }, { sort: { number: -1 } }, (error, food) =>
      assert.equal food.number, 100
      @next()

runner.mettle ->
  @tell 'insert duplicate'
  @db.insert 'Country', @iceland, (error, document) =>
    assert.equal error.code, 11000
    @next()

runner.mettle ->
  @tell 'remove by query'
  @db.remove 'Country', { _id: 1 }, (error) =>
    assert.equal error, null
    @db.find 'Country', { _id: 1 }, (error, documents) =>
      assert.equal documents.length, 0
      @next()

runner.mettle ->
  @tell 'insert with custom id factory'
  idfactory = (collection, next) ->
    next null, 'factory'
  db = new mongo.Database 'test', { idfactory: idfactory }
  doc_given = { name: 'Iceland', population: 316252 }
  db.insert 'Country', doc_given, (error, doc_taken) =>
    assert.equal error, null
    doc_given._id = 'factory'
    assert.deepEqual doc_given, doc_taken
    db.remove 'Country', { _id: 'factory' }, (error) =>
      assert.equal error, null
      db.find 'Country', { _id: 'factory' }, (error, documents) =>
        assert.equal documents.length, 0
        db.close()
        @next()

# XXX: Need connection pool limits for this
# runner.mettle ->
#   @count 500
#   @tell 'insert set of 500 in parallel'
#   for i in [1..500]
#     @db.insert 'Number', { value: i }, (error, document) =>
#       @next()

runner.mettle ->
  @count 10
  @tell 'insert set of 10 in parallel'
  for i in [1..10]
    @db.insert 'Number', { value: i }, (error, document) =>
      @next()

runner.mettle ->
  @tell 'find one'
  @db.find_one 'Number', (error, document) =>
    assert.equal error, null
    assert.notEqual document, null
    @next()

runner.mettle ->
  @tell 'update'
  pets = [{ name: 'Barky', species: 'Dog', age: 7 },
          { name: 'Homer', species: 'Cat', age: 9 },
          { name: 'Regus', species: 'Pig', age: 7 }]
  @db.insert 'Pet', pets[0], (error, document) =>
    @db.insert 'Pet', pets[1], (error, document) =>
      @db.insert 'Pet', pets[2], (error, document) =>
        @db.update 'Pet', { age: 7 }, { $set: { species: 'Weasel' } }, (error) =>
          assert.equal error, null
          @db.find 'Pet', { species: 'Weasel' }, (error, pets) =>
            assert.equal error, null
            assert.equal pets.length, 2
            @db.remove 'Pet', (error) =>
              @next()

runner.mettle ->
  @tell 'find and modify'
  @db.insert 'fm', { key: 'test' }, (id) =>
    @db.modify 'fm', { new: true, query: { key: 'test' }, update: { $inc: { value: 1 }}, fields: { value: 1 }}, (error, document) =>
      assert.equal error, null
      assert.equal document.value, 1
      @db.modify 'fm', { new: true, query: { key: 'test' }, update: { $inc: { value: 1 }}, fields: { value: 1 }}, (error, document) =>
        assert.equal error, null
        assert.equal document.value, 2
        @db.remove 'fm', =>
          @next()

runner.mettle ->
  @tell 'index'
  @iceland = { name: 'Iceland', population: 316252 }
  @db.insert 'Country', @iceland, (error, document) =>
    assert.equal error, null
    @db.index 'Country', { name: true, population: false }, (error) =>
      assert.equal error, null
      @db.index 'Country', { name: false }, (error) =>
        assert.equal error, null
        @db.find 'system.indexes', { ns: 'test.Country' }, (error, indexes) =>
          assert.equal error, null
          assert.equal indexes.length, 3
          @db.removeIndex 'Country', 'name', (error) =>
            assert.equal error, null
            @db.removeIndex 'Country', 'population', (error) =>
              assert.equal error, null
              @db.find 'system.indexes', { ns: 'test.Country' }, (error, indexes) =>
                assert.equal error, null
                assert.equal indexes.length, 1
                @db.remove 'Country', =>
                  @next()

runner.mettle ->
  @tell 'capped collection'
  @db.create 'Planet', { capped: true, size: 1000, max: 1 }, (error) =>
    @db.insert 'Planet', { name: 'Mercury' }, (error, document) =>
      @db.insert 'Planet', { name: 'Venus' }, (error, document) =>
        @db.find 'Planet', { }, (error, documents) =>
          assert.equal documents.length, 1
          assert.equal documents[0].name, 'Venus'
          @next()