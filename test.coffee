{parseFile} = require './parser'
{gen} = require './js-codegen'
{gridExtents, printGrid, moveShuttle} = require './util'

assert = require 'assert'
fs = require 'fs'

Simulator = require 'boilerplate-sim'

compile = (filename) ->
  buffer = []
  # I could use a real stream here, but then my test would be asyncronous.
  stream =
    write: (str) -> buffer.push str
    end: ->

  ast = parseFile filename
  gen ast, stream, module:'bare'

  code = buffer.join ''

  #console.log 'code length', code.length
  #console.log code
  f = new Function(code)
  {states, step} = f()
  {states, step, ast}


describe 'compiler', ->
  describe 'from test data', ->
    files = fs.readdirSync "#{__dirname}/testdata"

    for filename in ['elevator.json']
    #for filename in files when filename.match /\.json$/
      do (filename) -> it filename, ->
        cData = compile "testdata/#{filename}"

        # The compiler's grid
        grid1 = cData.ast.grid

        # The simulator's grid
        grid2 = {}
        grid2[k] = v for k,v of grid1

        sim = new Simulator grid2

        extents = cData.ast.extents || gridExtents grid1

        prevStates = new Uint32Array cData.states

        # Might be better to use the same logic thats in the simulator's
        # makedata instead of just guessing a number of steps to run.
        for [1..20]
          cData.step()
          for stateid,sid in cData.states when stateid != prevStates[sid]
            moveShuttle grid1, cData.ast.shuttles, sid, prevStates[sid], stateid
            prevStates[sid] = stateid

          sim.step()

          console.log '\n Compiler grid:\n'
          printGrid extents, grid1
          console.log '\n Simulator grid:\n'
          printGrid extents, grid2
          console.log '\n'
          console.log JSON.stringify(grid1)
          console.log JSON.stringify(grid2)
          assert.deepEqual grid1, grid2



