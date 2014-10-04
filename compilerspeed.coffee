compiler = require './index'
{gridExtents, printGrid, moveShuttle} = compiler.util

fs = require 'fs'

compile = (filename, fillMode) ->
  buffer = []
  # I could use a real stream here, but then my test would be asyncronous.
  stream =
    write: (str) -> buffer.push str
    end: ->

  t = Infinity

  for [1..5]
    start = Date.now()
    ast = compiler.compileFile filename, {stream, module:'bare', fillMode}
    end = Date.now()

  t = end - start if end - start < t

  #code = buffer.join ''

  t


total = 0

files = fs.readdirSync "#{__dirname}/testdata"
for fillMode in ['shuttles', 'engines']
  for filename in files when filename.match /^[^_].*\.json$/ # Ignore files starting in _
    time = compile "testdata/#{filename}", fillMode
    total += time

console.log total

