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

  elseIdx = -1

  do ->
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
      else if lastKey == key
        lastForce.distance++
        # >= so the biggestStateForce will prefer to be a late one.
        if lastForce.distance >= elseDistance
          elseDistance = lastForce.distance
          elseIdx = byState.length - 1
      else
        lastKey = key
        lastForce = stateforce
        byState.push stateforce

    #console.log @global, @byState, @exhaustive
    #console.log bs for bs in @byState
    
    elseIdx = -1 if !exhaustive


  # ***** Emit

  # There's no force. The shuttle won't move on its own.
  return no if !global.length && !byState.length


  pressureExpr = (rid) ->
    if opts.fillMode is 'engines'
      # In engine fill mode, some dependant regions haven't been calculated this tick.
      "(zone = regionZone[#{rid}] - base, zone < 0 ? 0 : zonePressure[zone])"
    else
      "zonePressure[regionZone[#{rid}] - base]"

  forceExpr = (mult, rid) ->
    # An expression for multiplier * <pressure in rid>
    multExpr = if mult is 1 then '+' else if mult is -1 then '-' else "+ #{mult}*"
    "#{multExpr} #{pressureExpr(rid)}"

  writeForceExpr = (list, isAlreadySet) ->
    W "force #{if isAlreadySet then '+=' else '='}"
    W.block ->
      for {rid, mult} in list
        W "#{forceExpr mult, rid}"
    W ";"


  # isAlreadySet: Is the force variable reset from the previous calculation?
  isAlreadySet = if global.length
    writeForceExpr global
    yes
  else
    no

  return yes if byState.length is 0

  #numRemaining = @byState.length



  W "state = shuttleState[#{sid}];"


  numSmallConditions = 0
  numSmallConditions++ for stateforce in byState when stateforce.distance < 2

  first = true
  emitIfBlock = (stateforce) ->
    cond = shuttleInRangeExpr [], s.states.length, "state", stateforce.base, stateforce.distance
    W "#{if !first then 'else ' else ''}if (#{cond.join '&&'}) {"
    W.block ->
      writeForceExpr stateforce.list, isAlreadySet
    W "}"
    first = false

  if numSmallConditions <= 2
    # Use chained if statements for everything.
    for stateforce,i in byState when i != elseIdx
      emitIfBlock stateforce
    if elseIdx >= 0
      W "else {"
      W.block ->
        writeForceExpr byState[elseIdx].list, isAlreadySet
      W "}"
  else
    # Emit everything that spans a range, and we'll use a switch for everything else.
    for stateforce,i in byState when stateforce.distance > 2 && i != elseIdx
      stateforce.done = true
      emitIfBlock stateforce

    W "switch(state) {"
    W.block ->
      for stateforce,i in byState when !stateforce.done && i != elseIdx
        W "case #{sid}:" for sid in [stateforce.base...stateforce.base + stateforce.distance]
        W.block ->
          writeForceExpr stateforce.list, isAlreadySet
          W "break;"

      if elseIdx != -1
        W "default:"
        W.block ->
          writeForceExpr byState[elseIdx].list, isAlreadySet
    W "}"



  return

  # As we go through, each if-else will raise the state's minimum to proceed
  stateMin = 0
  for stateforce in @byState

    cond = shuttleInRangeExpr [], @numStates, "state", stateforce.base, stateforce.distance

    #@W "  if (



    return
    #if @exhaustive
      # Find the worst case

    # We have a few different options here:
    # - If there's only 1 or 2 byState expressions, emit if()s
    # - If there's many, but they're exhaustive, find the most complicated and make it the default (else) case
    # - If there's two, use if-else blocks
    # - Use if blocks anyway for all cases which are complicated.
    # Find any blocks with lots in common and emit if statements for them.
    for stateforce in @byState when stateforce.distance > 4
      @emitIfBlockFor stateforce, isAlreadySet
      stateforce.done = true
      numRemaining--

    #if numRemaining is 1


    if @byState.length == 1
      # Emit a single if block
      @emitIfBlockFor @byState[0]
      if !isAlreadySet
        @W "  else force = 0;"
      @W()
    else if numStatesWithPush > 1
      # Emit a switch
      @W "  switch(shuttleState[#{sid}]) {"
      for state,stateid in s.states when state.pushedBy.length
        @W "    case #{stateid}:"
        console.log state.pushedBy
        writeForceExpr state.pushedBy, s.pushedBy.length > 0
        @W "      break;"

      if !s.pushedBy.length
        @W "    default: force = 0;"
      @W "  }"

    @W "  if (force) {"


    ###

    # Figure out the successor.
    #
    # This is special cased because simple 2 state shuttles are _super_ common.
    if s.successors
      if s.states.length is 2
        @W "    shuttleState[#{sid}] = force < 0 ? #{s.successors[0]} : #{s.successors[1]};"
      else
        # Lookup the new shuttle state in our state map.
        #@W "    shuttleState[#{sid}] = force < 0 ? successors[#{s.successorIdx}] : successors[#{s.successorIdx + 1

    #else if s.su
    ###


    @W "  }"

    yes

  ###
  emit: ->
    # y first to match the behaviour of the simulator
    for d in ['y', 'x'] when @forces[d]

  ###




genCode = (parserData, stream, opts = {}) ->
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
    for s,sid in shuttles when s.initial != 0
      W "shuttleState[#{sid}] = #{s.initial};"

    W()

  do ->
    # Shuttle successor map.
    successorData = []
    # This map maps from successor list strings (12,2,1,3) to the position in
    # the successor map. Its used to dedup successor lists between shuttles.
    map = {}
    for s in shuttles when s.type is 'statemachine'
      for state in s.states
        # Add successors to the map
        key = state.successors.join ','
        idx = map[key]
        if !idx?
          idx = successorData.length
          successorData.push v for v in state.successors
          map[key] = idx
        state.successorIdx = idx

    if successorData.length
      W "var successors = [#{successorData.join ','}];"
      

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
      W.indentation++
  
      exclusivePressure = 0
      for eid in r.engines
        e = engines[eid]
        if e.exclusive
          exclusivePressure += e.pressure
        else
          W "addEngine(z, #{nonExclusiveMap[eid]}, #{e.pressure});"

      if exclusivePressure
        W "zonePressure[z - base] += #{exclusivePressure};"

      W()

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

        # Run length encode.
        distance = 1
        loop
          break if i+1 >= keys.length
          next = r.connections[keys[i+1]]
          break if next.rid != c.rid || next.sid != c.sid
          i++
          distance++

        conditions = ["regionZone[#{c.rid}] !== z"]
        shuttleInRangeExpr conditions, shuttles[c.sid].states.length, "shuttleState[#{c.sid}]", c.stateid, distance
        W "if (#{conditions.join ' && '}) calc#{c.rid}(z);"

        i++

      W.indentation--
      W "}"
    W()


  do -> # Step function
    W """
function step() {
  var nextZone = base;
"""
    W.indentation++

    # For each region, is it possible we've already figured out which zone its in?
    alreadyZoned = new Array regions.length

    fillFromRegion = (rid) ->
      return if alreadyZoned[rid] is true

      if alreadyZoned[rid]
        W "if (regionZone[#{rid}] < base) {"
        W.indentation++

      W "zonePressure[nextZone - base] = 0;"
      W "calc#{rid}(nextZone++);"

      if alreadyZoned[rid]
        W.indentation--
        W "}"

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
        W "var zone;"
        # Calculate the pressure of all regions which connect to an engine.
        # (And everything else can be inferred to have 0 pressure).
        for e in engines
          fillFromRegion rid for rid in e.regions

    W()




    # Update the state of all shuttles
    W "var force, state;"
    for s,sid in shuttles when !s.immobile
      W "\n// Calculating force for shuttle #{sid}"


      for d in ['x', 'y'] when s.moves[d]
        W "// #{d}"
        emitForceExpr(opts, W, sid, s, d)

      #force = 


    W "base = nextZone;"
    W.indentation--
    W "}\n"


if require.main == module
  {parseFile} = require('./parser')
  #filename = 'and-or2.json'
  filename = 'exclusive.json'
  filename = 'cpu.json'
  filename = 'elevator.json'
  #filename = 'oscillator.json'
  data = parseFile process.argv[2] || filename
  genCode data, process.stdout, debug:true, fillMode:'shuttles', module:'pure'


