class Runner
  constructor: ->
    @_final_titles = []
    @_final_tests  = []
    @_final_counts = []
    @_titles    = []
    @_tests     = []
    @_counts    = []
    @_titlesize = 0
    @_title     = ''
    @_i         = 0
    @_dir       = '.'

  dir: (dir) ->
    @_dir = dir

  load: (suite) ->
    @_title = suite
    require @_dir + '/' + suite

  mettle: (title, test) ->
    if not test?
      test = title
      title = @_title
    @_titlesize = Math.max(@_titlesize, title.length)
    @_titles.push title
    @_tests.push test
    @_counts.push 1

  settle: (title, test) ->
    if not test?
      test = title
      title = @_title
    @_titlesize = Math.max(@_titlesize, title.length)
    @_final_titles.unshift title
    @_final_tests.unshift test
    @_final_counts.unshift 1

  count: (count) ->
    @_counts[@_i] = count

  next: ->
    return if @_tests.length == 0
    if @_i < @_tests.length
      if @_tests[@_i]
        test = @_tests[@_i]
        @_tests[@_i] = null
        test.apply @
      else
        @_counts[@_i]--
      if @_counts[@_i] == 0
        @_i++
        @_titles[@_i] = @_titles[@_i - 1] if @_titles[@_i] == ''
        @next()
    else
      @_titles = @_final_titles
      @_tests = @_final_tests
      @_counts = @_final_counts
      @_i = 0
      @next()

  tell: (message) ->
    puts [ ansi.off
           '[ '
           ansi.yellow
           (@_titles[@_i] + Array(@_titlesize).join ' ').slice(0, @_titlesize)
           ansi.off
           ' ] '
           message
           ansi.bold
           ansi.black
         ].join('')

module.exports = new Runner
