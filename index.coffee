exports.util = require './util'
{parse, parseFile} = require './parser'
{gen} = require './js-codegen'

exports.parse = parse
exports.parseFile = parseFile
exports.genJS = gen

# Compile the grid in the named file. Output will either be opts.stream or
# standard out.
exports.compileFile = (filename, opts) ->
  ast = parseFile filename, opts
  gen ast, opts.stream, opts

# Compile the specified grid. Output will either be opts.stream or standard
# out.
exports.compileGrid = (grid, opts) ->
  ast = parse grid, opts
  gen ast, opts.stream, opts

