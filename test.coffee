{parseFile} = require './parser'
{gen} = require './js-codegen'

{Writable} = require 'stream'


buffer = []

stream = new Writable decodeStrings:no
stream._write = (chunk, encoding, cb) ->
  buffer.push chunk.toString()
  cb()

stream.on 'finish', ->
  code = buffer.join ''
  console.log code.length
  console.log code
  f = new Function(code)
  {states, step} = f()

  console.log (states[i] for i in [0...states.length])

data = parseFile 'testdata/cross.json'
gen data, stream, module:'bare'

