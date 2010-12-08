runner.settle ->
  @db.close()
  @next()

runner.mettle ->
  @db = new mongo.Database 'test'
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
  db = new mongo.Database 'test', (collection, next) ->
    next null, 'factory'
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
  @tell 'clear'
  @db.remove 'Number', (error) =>
    assert.equal error, null
    @db.find_one 'Number', (error, document) =>
      assert.equal document, null
      @next()

runner.mettle ->
  @tell 'update'
  pets = [{ name: 'Barky', species: 'Dog', age: 7 },
          { name: 'Homer', species: 'Cat', age: 9 },
          { name: 'Regus', species: 'Pig', age: 7 }]
            assert.equal pets.length, 3
            # Alternative syntax
            @db.update 'Pet', { query: { species: 'Weasel' }, update: { $set: { species: 'Jackalope' } }, multi: true }, (error) =>
              assert.equal error, null
              @db.find 'Pet', { species: 'Jackalope' }, (error, pets) =>
                assert.equal error, null
                assert.equal pets.length, 3
                @db.remove 'Pet', (error) =>
                  @next()
            assert.equal pets.length, 2
            @db.clear 'Pet', (error) =>
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
