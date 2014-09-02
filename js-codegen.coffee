# This script takes a parsed boilerplate program and translates it into javascript.
#
# It might have made sense to use escodegen for this instead of outputting the
# result directly.

util = require './util'

uintArray = (max) ->
  if max < 256
    'Uint8Array'
  else if max < 2**16
    'Uint16Array'
  else if max < 2**32
    'Uint32Array'
  else
    'Uint64Array'

intArray = (max) ->
  if max < 127
    'Int8Array'
  else if max < 2**15
    'Int16Array'
  else if max < 2**31
    'Int32Array'
  else
    'Int64Array'


genCode = (parserData, stream, opts = {}) ->
  # Headers and stuff.

  W = (str = '') -> stream.write str + '\n'


  W "// Generated from boilerplate-compiler v0\n"

  if opts.debug
    W "/* Compiled grid\n"

    {extents, grid, edgeGrid} = parserData
    extents ||= util.gridExtents grid
    util.printGrid extents, grid, stream
    util.printEdges extents, grid, edgeGrid, stream

    W "*/\n"
  
  {shuttles, regions, engines} = parserData

  do -> # Variables
    maxStates = 0
    for s in shuttles
      #console.log s
      maxStates = s.states.length if s.states.length > maxStates

    W """
var shuttleState = new #{uintArray maxStates}(#{shuttles.length});
var regionZone = new Uint64Array(#{regions.length});
var base = 1;

var zonePressure = new #{intArray engines.length}(#{regions.length});

"""

  nonExclusiveMap = {}
  do -> # Non-exclusive engine code block
    # Its possible that an engine will be used by multiple zones, and we need to
    # dedup the pressure.
    num = 0

    for e,eid in engines
      if !e.exclusive
        nonExclusiveMap[eid] = num++

    if num
      W """
var engineLastUsedBy = new Uint64Array(#{num});

// Only used for exclusive engines
function addEngine(zone, engine, engineValue) {
  if (engineLastUsedBy[engine] != zone) {
    zonePressure[zone - base] += engineValue;
    engineLastUsedBy[engine] = zone;
  }
}

"""

  do -> # Region flood fills
    for r,rid in regions
      W """
function calc#{rid}(z) {
  regionZone[#{rid}] = z;
"""
  
      exclusivePressure = 0
      for eid in r.engines
        e = engines[eid]
        if e.exclusive
          exclusivePressure += e.pressure
        else
          W "  addEngine(z, #{nonExclusiveMap[eid]}, #{e.pressure});"

      if exclusivePressure
        W "  zonePressure[z - base] += #{exclusivePressure};"

      W()

      # Connections
      for k, c of r.connections
        W "  if (regionZone[#{c.rid}] !== z && shuttleState[#{c.sid}] === #{c.stateid}) calc#{c.rid}();"

      W "}"
    W()


  do -> # Step function
    W """
function step() {
  var nextZone = base;
"""

    # For each region, is it possible we've already figured out which zone its in?
    alreadyZoned = new Array regions.length

    fillFromRegion = (rid) ->
      return if alreadyZoned[rid] is true
      W "  if (regionZone[#{rid}] < base) {" if alreadyZoned[rid]

      W "  zonePressure[nextZone - base] = 0;"
      W "  calc#{rid}(nextZone++);"
      W "  }" if alreadyZoned[rid]

      util.fillRegions regions, rid, (rid, trace) ->
        if alreadyZoned[rid]
          no
        else
          alreadyZoned[rid] = 'maybe'
          yes
      alreadyZoned[rid] = true

    opts.fillMode ?= 'all'
    switch opts.fillMode
      when 'all'
        # Flood fill all regions. Good for debugging, but does more work than necessary.
        fillFromRegion rid for rid in [0...regions.length]
      when 'shuttles'
        # Calculate only the pressure of regions which touch a shuttle
        for s in shuttles
          for k of s.pushedBy
            fillFromRegion +k
          for state in s.states
            for k of state.pushedBy
              fillFromRegion +k
      when 'engines'
        W "  var zone;"
        # Calculate the pressure of all regions which connect to an engine.
        # (And everything else can be inferred to have 0 pressure).
        for e in engines
          fillFromRegion rid for rid in e.regions

    W()

    pressureExpr = (rid) ->
      if opts.fillMode is 'engines'
        # In engine fill mode, some dependant regions haven't been calculated this tick.
        "(zone = #{rid} - base, zone < 0 ? 0 : zonePressure[zone])"
      else
        "zonePressure[#{rid} - base]"

    forceExpr = (mult, rid) ->
      # An expression for multiplier * <pressure in rid>
      multExpr = if mult is 1 then '+' else if mult is -1 then '-' else "+ #{mult}*"
      "#{multExpr} #{pressureExpr(rid)}"

    writeForceExpr = (pushedBy, shouldAdd) ->
      W "  force #{if shouldAdd then '+=' else '='}"
      for p in pushedBy
        rid = p.rid
        mult = p["m#{d}"]
        continue unless mult
        W "    #{forceExpr mult, rid}"
      W "    ;"

    # Update the state of all shuttles
    W "  var force;"
    for s,sid in shuttles when !s.immobile
      #console.log s.pushedBy
      for d in ['x', 'y'] when s.moves[d]
        W "\n  // Calculating #{d} force for shuttle #{sid}"
        writeForceExpr s.pushedBy if s.pushedBy.length

        numStatesWithPush = 0
        numStatesWithPush++ for state in s.states when state.pushedBy.length

        if numStatesWithPush == 1
          # Emit an if block
          for state,stateid in s.states when state.pushedBy.length
            #console.log state.pushedBy
            W "  if (shuttleState[#{sid}] == #{stateid}) {"
            writeForceExpr state.pushedBy, s.pushedBy.length > 0
            W "  }"
            if !s.pushedBy.length
              W "  else force = 0;"
        else if numStatesWithPush > 1
          # Emit a switch
          W "  switch(shuttleState[#{sid}]) {"
          for state,stateid in s.states when state.pushedBy.length
            W "    case #{stateid}:"
            writeForceExpr state.pushedBy, s.pushedBy.length > 0
            W "      break;"

          if !s.pushedBy.length
            W "    default: force = 0;"
          W "  }"

        W "  if (force) {"

        W "  }"




      #force = 


    W "  base = nextZone;"
    W "}\n"


if require.main == module
  {parseFile} = require('./parser')
  #filename = 'and-or2.json'
  filename = 'exclusive.json'
  #filename = 'cpu.json'
  #filename = 'oscillator.json'
  data = parseFile filename
  genCode data, process.stdout, debug:true, fillMode:'shuttles', module:'pure'


