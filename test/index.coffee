global.util     = require 'util'
global.put      = (args...) -> util.print a for a in args
global.puts     = (args...) -> put args.join '\n'
global.p        = (args...) -> puts util.inspect(a, true, null) for a in args
global.pl       = (args...) -> put args.join(', ') + '\n'
global.assert   = require 'assert'
global.ansi     = require './ansi'
global.runner   = require './runner'
# global.mongo    = require '../lib/mongo'
global.bson     = require '../lib/bson'

global.timeout  = (time, next) -> setTimeout next, time
global.interval = (time, next) -> setInterval next, time

process.on 'SIGINT', ->
  process.exit()
process.on 'exit', ->
  put ansi.off

runner.dir __dirname
runner.load 'bson'
# runner.load 'mongo'
# runner.load 'congo'
runner.next()

