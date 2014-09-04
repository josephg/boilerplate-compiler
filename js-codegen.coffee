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
  else
    'Uint32Array'

intArray = (max) ->
  if max < 127
    'Int8Array'
  else if max < 2**15
    'Int16Array'
  else
    'Int32Array'


shuttleInRangeExpr = (dest, numStates, stateExpr, base, distance) ->
  if distance == 1 && numStates > 0
    dest.push "#{stateExpr} === #{base}"
  else
    end = base + distance
    dest.push "#{stateExpr} >= #{base}" if base && base > 0
    dest.push "#{stateExpr} < #{end}" if end < numStates
  dest


# The pushedBy list is pitifully lacking for our purposes here. Rewrite
# it again into a run-length encoded list of shuttle list &
# rid/multiplier pairs in each direction.
emitForceExpr = (opts, W, sid, s, d) ->
  #console.log s.pushedBy, (state.pushedBy for state in s.states)

  throw 'Shuttle does not move in direction!' unless s.moves[d]


  # Forces on the shuttle in all positions
  global = []

  # Forces on the shuttle in some positions (list of {base, numStates, list})
  byState = []

  # Does byState cover all shuttle states?
  exhaustive = yes

  elseForce = null
  do ->
    elseIdx = -1
    elseDistance = 0

    # First calculate the global (common) forces on the shuttle
    for p in s.pushedBy
      mult = p["m#{d}"]
      if mult
        global.push {rid:p.rid, mult}

    # Scan through all the states. Run-length encode the force for states which
    # share the same forces.
    lastForce = null
    lastKey = null
    for state, stateid in s.states
      # I know string concatenation is the devil's plaything in node, but eh.
      stateforce = {base:stateid, distance:1, list:[]}
      key = ""
      for p in state.pushedBy
        mult = p["m#{d}"]
        continue unless mult
        stateforce.list.push {rid:p.rid, mult}
        key += "#{p.rid} #{mult} "

      if stateforce.list.length is 0
        lastKey = null
        exhaustive = no
      else
        if lastKey == key
          lastForce.distance++
          # >= so the biggestStateForce will prefer to be a late one.
        else
          lastKey = key
          lastForce = stateforce
          byState.push stateforce

        if lastForce.distance >= elseDistance
          elseDistance = lastForce.distance
          elseIdx = byState.length - 1

    #console.log @global, @byState, @exhaustive
    #console.log bs for bs in @byState
    
    if exhaustive
      #console.log 'sss', elseIdx
      elseForce = byState[elseIdx]

  # ***** Emit

  # There's no force. The shuttle won't move on its own.
  return no if !global.length && !byState.length

  W "\n// Calculating force for shuttle #{sid} (#{s.type}) with #{s.states.length} states"

  pressureExpr = (rid) ->
    if opts.fillMode is 'engines'
      # In engine fill mode, some dependant regions haven't been calculated this tick.
      "(z = regionZone[#{rid}] - base, z < 0 ? 0 : zonePressure[z])"
    else
      "zonePressure[regionZone[#{rid}] - base]"

  forceExpr = (mult, rid) ->
    # An expression for multiplier * <pressure in rid>
    multExpr = if mult is 1 then '+' else if mult is -1 then '-' else "+ #{mult}*"
    "#{multExpr} #{pressureExpr(rid)}"

  writeForceExpr = (list) ->
    W.block ->
      for {rid, mult} in list
        W "#{forceExpr mult, rid}"

  writeForceStatement = (list, isAlreadySet) ->
    W "force #{if isAlreadySet then '+=' else '='}"
    W.block ->
      for {rid, mult} in list
        W "#{forceExpr mult, rid}"
    W ";"

  # isAlreadySet: Is the force variable reset from the previous calculation?
  isAlreadySet = if global.length
    writeForceStatement global
    yes
  else
    no

  if s.type != 'shuttle' || byState.length > 0
    W "state = shuttleState[#{sid}];"

  return yes if byState.length is 0

  numSmallConditions = 0
  numSmallConditions++ for stateforce in byState when stateforce.distance < 2

  # This emits (cond) ? expr : 
  emitTernary = (stateforce) ->
    cond = shuttleInRangeExpr [], s.states.length, "state", stateforce.base, stateforce.distance
    W "(#{cond.join '&&'}) ? ("
    writeForceExpr stateforce.list
    W ") :"

  if numSmallConditions <= 2
    #console.log 'elseforce', elseForce, exhaustive
    # Use chained if statements for everything.
    W "force #{if isAlreadySet then '+=' else '='}"
    W.block ->
      for stateforce,i in byState when stateforce != elseForce
        emitTernary stateforce

      if elseForce
        if elseForce.distance > 1
          W "  // States #{elseForce.base} to #{elseForce.base + elseForce.distance - 1}"
        else
          W "  // State #{elseForce.base}"

        writeForceExpr elseForce.list, isAlreadySet
        W ";"
      else
        W "0;"
  else
    # Emit everything that spans a range, and we'll use a switch for everything else.
    emittedOne = false
    for stateforce in byState when stateforce.distance > 2 && stateforce != elseForce
      if !emittedOne
        W "force #{if isAlreadySet then '+=' else '='}"
        W.indentation++

      for stateforce,i in byState when stateforce != elseForce
        emitTernary stateforce

      emittedOne = true
      stateforce.done = true
    if emittedOne
      W "0;"
      W.indentation--

    W "switch(state) {"
    W.block ->
      for stateforce in byState when !stateforce.done && stateforce != elseForce
        W "case #{sid}:" for sid in [stateforce.base...stateforce.base + stateforce.distance]
        W.block ->
          writeForceStatement stateforce.list, isAlreadySet
          W "break;"

      if elseForce
        W "default:"
        W.block ->
          writeForceStatement elseForce.list, isAlreadySet
    W "}"

  return yes

emitRegionCalcBody = (W, parserData, rid, nonExclusiveMap, opts) ->
  {path, zoneIdxExpr, wasCalculated} = opts
  # The path of regions we've travelled through, to make sure we don't loop.
  if path
    path.push rid
  else
    path = opts.path = [rid]

  wasCalculated[rid] = true if wasCalculated

  {regions, shuttles, engines} = parserData
  r = regions[rid]

  W "regionZone[#{rid}] = z;"

  exclusivePressure = 0
  for eid in r.engines
    e = engines[eid]
    if e.exclusive
      exclusivePressure += e.pressure
    else
      W "addEngine(z, #{nonExclusiveMap[eid]}, #{e.pressure});"

  if opts.setBasePressure
    W "zonePressure[#{zoneIdxExpr}] = #{exclusivePressure};"
    # Only forcably set pressure in the root of an inline tree.
    opts.setBasePressure = no
  else if exclusivePressure > 0
    W "zonePressure[#{zoneIdxExpr}] += #{exclusivePressure};"
  else if exclusivePressure < 0
    W "zonePressure[#{zoneIdxExpr}] -= #{-exclusivePressure};"

  W()

  #console.log r.connections

  # Connections
  keys = Object.keys(r.connections).sort (a, b) ->
    a = r.connections[a]
    b = r.connections[b]
    if a.rid != b.rid
      a.rid - b.rid
    else if a.sid != b.sid
      a.sid - b.sid
    else
      a.stateid - b.stateid

  # Coffeescript for loops are too clever.
  i = 0
  while i < keys.length
    c = r.connections[keys[i]]

    r2 = regions[c.rid]
    #console.log 'considering connection', c
    if r2.used is 'primaryOnly' || c.rid in path
      #console.log '-> Skipped!'
      i++
      continue

    #console.log "#{rid} <-> #{c.rid} #{c.stateid}"

    # Run length encode.
    distance = 1
    loop
      break if i+1 >= keys.length
      next = r.connections[keys[i+1]]
      break if next.rid != c.rid || next.sid != c.sid
      break if next.stateid != c.stateid + distance
      i++
      distance++

    conditions = []
    conditions.push "regionZone[#{c.rid}] !== z" if !wasCalculated || wasCalculated[c.rid]
    shuttleInRangeExpr conditions, shuttles[c.sid].states.length, "shuttleState[#{c.sid}]", c.stateid, distance

    if r2.inline
      W "if (#{conditions.join ' && '}) {"
      W.block ->
        emitRegionCalcBody W, parserData, c.rid, nonExclusiveMap, opts
      W "}"
    else
      W "if (#{conditions.join ' && '}) calc#{c.rid}(z);"

      if wasCalculated
        util.fillRegions regions, c.rid, (rid) ->
          return no if wasCalculated[rid]
          wasCalculated[rid] = true
          return yes

    i++

  # Remove myself off the end of the path list.
  path.pop()


genCode = (parserData, stream, opts = {}) ->
  opts.fillMode ?= 'all'
  throw Error 'fillMode must be all, shuttles or engines' unless opts.fillMode in ['all', 'shuttles', 'engines']
  # Headers and stuff.

  W = (str = '') ->
    lines = str.split '\n'
    for l in lines
      stream.write '  ' for [0...W.indentation]
      stream.write l + '\n'
  W.indentation = 0
  W.block = (f) ->
    W.indentation++
    f()
    W.indentation--

  {shuttles, regions, engines} = parserData

  W "// Generated from boilerplate-compiler v1 in fill mode '#{opts.fillMode}'"
  W "// #{shuttles.length} shuttles, #{regions.length} regions and #{engines.length} engines"

  if opts.debug && regions.length < 20
    W "/* Compiled grid\n"

    {extents, grid, edgeGrid} = parserData
    extents ||= util.gridExtents grid
    util.printGrid extents, grid, stream
    util.printEdges extents, grid, edgeGrid, stream

    W "*/\n"
  
  W "(function(){" if opts.module isnt 'bare'

  # Map from shuttle ID -> offset in the successor map.
  successorPtrs = null

  do -> # Variables
    maxStates = 0
    for s in shuttles
      #console.log s
      maxStates = s.states.length if s.states.length > maxStates

    W """
var shuttleState = new #{uintArray maxStates}(#{shuttles.length});
var regionZone = new Uint32Array(#{regions.length});
var base = 1;

var zonePressure = new #{intArray engines.length}(#{regions.length});
"""

    # Shuttle successor map.
    successorData = []
    # This map maps from successor list strings (12,2,1,3) to the position in
    # the successor map. Its used to dedup successor lists between shuttles.
    #
    # This is very fancy, but it doesn't happen often. Its probably not worth it.
    for s,sid in shuttles when s.type is 'statemachine'
      successorPtrs ||= {}
      successorPtrs[sid] = successorData.length
      for state in s.states
        successorData.push v for v in state.successors

    if successorData.length
      W "var successors = [#{successorData.join ','}];"

    W()
    for s,sid in shuttles when s.initial != 0
      W "shuttleState[#{sid}] = #{s.initial};"
    W()
      

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
var engineLastUsedBy = new Uint32Array(#{num});

// Only used for exclusive engines
function addEngine(zone, engine, engineValue) {
  if (engineLastUsedBy[engine] != zone) {
    zonePressure[zone - base] += engineValue;
    engineLastUsedBy[engine] = zone;
  }
}

"""

  do -> # Region flood fills


    # primaryOnly: recurse _to_ anywhere is ok, nobody can enter.
    # primary: entrances = number of connections + 1
    # transitive: entrances = number of connections.
    #
    # if (primaryOnly || entrances <= 2) inline else make fn.

    fillFromRegion = (rid) ->
      r = regions[rid]
      if !r.used
        r.used = 'primaryOnly'
      else
        r.used = 'primary'

      util.fillRegions regions, rid, (rid, trace) ->
        r = regions[rid]

        #console.log "inline #{rid}" if r.inline

        return no if r.used is 'transitive'
        return yes if r.used
        r.used = 'transitive'
        return yes

    # First find which regions are actually used.
    switch opts.fillMode
      when 'all'
        # Flood fill all regions. Good for debugging, but does more work than necessary.
        fillFromRegion rid for rid in [0...regions.length]
      when 'shuttles'
        # Calculate only the pressure of regions which touch a shuttle
        for s in shuttles
          for k in s.pushedBy
            fillFromRegion k.rid
          for state in s.states
            for k in state.pushedBy
              fillFromRegion k.rid
      when 'engines'
        # Calculate the pressure of all regions which connect to an engine.
        # (And everything else can be inferred to have 0 pressure).
        for e in engines
          fillFromRegion rid for rid in e.regions

    for r in regions
      numConnections = util.numKeys r.connections
      r.inline = switch r.used
        when 'primaryOnly'
          yes
        when 'primary'
          numConnections <= 1
        when 'transitive'
          numConnections <= 2
        else
          no

    for r,rid in regions when r.used && !r.inline
      W """
function calc#{rid}(z) {
"""
      W.block ->
        emitRegionCalcBody W, parserData, rid, nonExclusiveMap, zoneIdxExpr:'z - base'
      W "}"
    W()


  do -> # Step function
    W "function step() {"
    W.block ->
      W "var nextZone = base;"

      # For each region, is it possible we've already figured out which zone its in?
      alreadyZoned = new Array regions.length


      zoneIdx = 0
      varzSet = false
      # Mark zones when we might have already traversed them. If we have
      # definitely never traversed something, we can drop a conditional.
      wasCalculated = {}
      for r,rid in regions when r.used in ['primary', 'primaryOnly']
        W "// Calculating zone for region #{rid}"
        if r.used is 'primary'
          zoneIdx = -1
          W "if (regionZone[#{rid}] < base) {"
          W.indentation++

        zoneIdxExpr = if zoneIdx == -1
          if r.inline
            "z - base"
          else
            "nextZone - base"
        else
          "#{zoneIdx++}"

        if r.inline
          if !varzSet
            W "var z;"
            varzSet = true
          W "z = nextZone++;"
          emitRegionCalcBody W, parserData, rid, nonExclusiveMap, {zoneIdxExpr, setBasePressure:yes, wasCalculated}
        else
          W "zonePressure[#{zoneIdxExpr}] = 0;"
          W "calc#{rid}(nextZone++);"

        if r.used is 'primary'
          W.indentation--
          W "}"

      W()

      # Update the state of all shuttles
      W "var force, state;"
      W "var successor;" if successorPtrs
      for s,sid in shuttles when !s.immobile
        switch s.type
          when 'switch', 'track'
            # Only 1 of these will be true anyway.
            for d in ['x', 'y'] when s.moves[d]
              isForce = emitForceExpr opts, W, sid, s, d
              continue unless isForce

              if s.type is 'switch'
                W "if (force) shuttleState[#{sid}] = force < 0 ? 0 : 1;"
              else if s.type is 'track'
                W "if (force < 0 && state > 0) --shuttleState[#{sid}];"
                W "else if (force > 0 && state < #{s.states.length - 1}) ++shuttleState[#{sid}];"

          when 'statemachine'
            # These are a lot more 'fun'.
            #
            # We need to calculate the y direction first. If it doesn't move, we
            # calculate the x direction.

            W "// Y direction:"
            isYForce = emitForceExpr opts, W, sid, s, 'y'

            successorPtr = successorPtrs[sid]
            if isYForce
              W "successor = force === 0 ? state : successors[(force > 0 ? #{1 + successorPtr} : #{successorPtr}) + 4 * state];"
              W "if (successor === state) {"
              W.indentation++

            W "// X direction:"
            isXForce = emitForceExpr opts, W, sid, s, 'x'
            if isXForce
              W "successor = force === 0 ? state : successors[(force > 0 ? #{3 + successorPtr} : #{2 + successorPtr}) + 4 * state];"
            if isYForce
              W.indentation--
              W "}"

            if isXForce || isYForce
              W "shuttleState[#{sid}] = successor;"

      W "base = nextZone;"
    W "}\n"

    if opts.module is 'node'
      W "module.exports = {states:shuttleState, step:step};"
    else
      W "return {states:shuttleState, step:step};"

    W "})();" if opts.module isnt 'bare'


if require.main == module
  {parseFile} = require('./parser')
  #filename = 'and-or2.json'
  filename = 'exclusive.json'
  filename = 'cpu.json'
  filename = 'elevator.json'
  #filename = 'oscillator.json'
  data = parseFile process.argv[2] || filename
  genCode data, process.stdout, debug:true, fillMode:'shuttles', module:'node'


