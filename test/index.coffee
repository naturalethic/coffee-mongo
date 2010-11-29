global.util   = require 'util'
global.put    = (args...) -> util.print(a) for a in args
global.puts   = (args...) -> put(a + '\n') for a in args
global.p      = (args...) -> puts(util.inspect(a, true, null)) for a in args
global.assert = require 'assert'
global.ansi   = require './ansi'
global.runner = require './runner'
# global.mongo  = require '../lib/mongo'
global.binary = require '../lib/binary'

process.on 'SIGINT', ->
  process.exit()
process.on 'exit', ->
  put ansi.off

runner.dir __dirname
runner.load 'binary'
# runner.load 'mongo'
# runner.load 'congo'
runner.next()

