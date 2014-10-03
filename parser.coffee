{parseXY, numKeys, fill, fillRegions, gridExtents, printGrid, printEdges} = util = require './util'

dirs =
  up: {dx:0,dy:-1}
  right: {dx:1,dy:0}
  down: {dx:0,dy:1}
  left: {dx:-1,dy:0}

edges = [
  {ex:0,ey:0,isTop:false,dx:-1,dy:0}
  {ex:0,ey:0,isTop:true,dx:0,dy:-1}
  {ex:1,ey:0,isTop:false,dx:1,dy:0}
  {ex:0,ey:1,isTop:true,dx:0,dy:1}
]

numericSort = (a, b) -> (a|0) - (b|0)
sortedKeys = (obj, fn = numericSort) -> Object.keys(obj).sort(fn)

# This is basically a big function, but there's a lot of shared data between
# the different helper functions. I'm using a class mostly so I can bind this.
class Parser
  constructor: (@grid) ->
    # These are the transient maps, which annotate the grid with references to the graph
    # map from grid position -> ID of shuttle
    @shuttleGrid = {}
    # map from grid position -> ID of engine
    @engineGrid = {}
    # map from "x,y,isTop" to id of region
    @edgeGrid = {}
    # map from grid position -> ID of region. Note that not all regions will be
    # represented here - this is mostly for displaying pressure while
    # rendering.
    @regionGrid = {}

    # This is our final output - a list of shuttles and regions which mutually affect one another.
    @shuttles = []
    @regions = []
    # The engine list is important for figuring out which regions share each
    # engine. Usually none will - but its part of the spec that they can.
    @engines = []

  # **** Helper functions
  get: (x,y) -> @grid["#{x},#{y}"]

  printPoint: (x, y) ->
    @extents ||= gridExtents @grid
    util.printPoint @extents, @grid, x, y

  parse: (@opts = {}) ->
    @debug ||= @opts.debug

    # For now.
    @opts.expensiveOptimizations = true

    # The drawing functions are the only thing that uses this.
    if @opts.debug
      @extents = gridExtents @grid
      printGrid @extents, @grid

    # Annotate the grid, marking engines and shuttles (in their current position)
    @annotateGrid()
    
    # Figure out all the places shuttles can move to, filling a cloud in the shuttle grid.
    @findShuttleStates s,sid for s,sid in @shuttles when !s.immobile

    # Find & fill all regions in the edge grid.
    @fillRegions()

    # For each region, figure out which other regions it can connect to and
    # which shuttles it pushes.
    @findRegionConnectionsAndShuttleForce()

    # Neutral regions are regions which can never hold pressure because they
    # aren't connected to any engines.
    @findNeutralRegions()

    # Trim pushedBy values in shuttles
    @cleanShuttlePush()

    # Figure out which engines (if any) are important in by multiple regions.
    @calculateEngineExclusivity e for e in @engines

    if @debug
      printEdges @extents, @grid, @edgeGrid


  annotateGrid: ->
    for k,v of @grid when k not in ['tw', 'th']
      {x,y} = parseXY k
      switch v
        when 'positive', 'negative'
          # Mark these - we'll need them later.
          id = @engines.length
          pressure = if v is 'positive' then 1 else -1
          @engines.push {x, y, pressure, regions:[]}
          @engineGrid["#{x},#{y}"] = id

        when 'shuttle', 'thinshuttle'
          # flood fill the shuttle extents.
          continue if @shuttleGrid["#{x},#{y}"]?

          id = @shuttles.length
          @shuttles.push s =
            points: {} # Grid of points in the shuttle in the base state
            fill: {} # Map from x,y -> [true if filled in state=index]
            states: [] # List of the {dx,dy,pushedBy} of each state
            adjacentTo: {} # Map from {x,y} -> [region id]
            moves: {x:false, y:false}
            immobile: v is 'thinshuttle' # Immobile if only thinshuttle, no states or no pressure possible.
            pushedBy: [] # List of {rid, mx, my} across all states

          # Flood fill the shuttle
          fill {x,y}, (x, y) =>
            v = @get x, y
            if v in ['shuttle', 'thinshuttle']
              s.immobile = false if s.immobile && @get(x,y) is 'shuttle'

              @shuttleGrid["#{x},#{y}"] = id
              s.points["#{x},#{y}"] = v
              true
            else
              false

  findShuttleStates: (s, sid) ->
    # Find all the places it can move to.
    extents = null
    fill {x:0, y:0}, (dx, dy) =>
      # x, y is an offset for the shuttle. Figure out if its viable.
      #
      # We'll assume that any shuttles are either part of the current
      # shuttle, or they'll move out of the way before we get there.
      for k of s.points
        {x,y} = parseXY k
        k = "#{x+dx},#{y+dy}"
        # Check that we aren't overlapping with another shuttle. (Technically
        # valid, but not allowed by this compiler)
        otherSid = @shuttleGrid[k]
        if otherSid? and otherSid != sid
          console.warn "Potentially overlapping shuttles at #{k}"
          return false

        if @grid[k] not in ['nothing', 'shuttle', 'thinshuttle']
          return false

      # pushedBy is a list of {rid,mx,my} multipliers.
      s.states.push {dx,dy, pushedBy:[], tempPushedBy:{}}

      s.moves.x = true if dx
      s.moves.y = true if dy

      #console.log 'it could move to ', dx, dy
      return true

    # Sort them by y then x (top to bottom, left to right)
    s.states.sort (a, b) -> if a.dy != b.dy then a.dy - b.dy else a.dx - b.dx

    # Fill @shuttleGrid and populate s.fill
    for state, stateid in s.states
      {dx,dy} = state

      s.initial = stateid if dx == 0 and dy == 0

      # Mark filled cells as impassable in this state.
      for k,v of s.points when v is 'shuttle'
        {x,y} = parseXY k
        _x = x+dx; _y = y+dy
        k = "#{_x},#{_y}"

        @shuttleGrid[k] = sid

        # s.fill is a map from x,y to [<true/falsey>] for passability in each state
        f = (s.fill[k] ?= [])
        f[stateid] = true

    # Figure out how we'll calculate the shuttle's successor states in the
    # generated code.
    #
    # 4 different types of shuttles:
    # - Immobile shuttles (only 1 state, which is the current state)
    # - Switches. These have 2 states, and if the force is positive, they'll
    #   move to the appropriate state.
    # - track shuttles. These slide along a single axis (x or y).
    # - Everything else. It might make sense to special-case long curved
    #   tracks at some point, but not yet.
    s.type = if s.states.length is 1
      s.immobile = true
      'immobile'
    else if s.states.length is 2
      # The two states are the left/up state (0) and the down/right state (1).
      # This is sort of a special case of a track and a special case of
      # statemachine (n=2)
      s.direction = if s.moves.x then 'x' else 'y'
      'switch'
    else if !s.moves.x or !s.moves.y
      # There's N states, 0...s.states.length. Force will push the shuttle
      # along the track until the state is 0 or length-1.
      s.direction = if s.moves.x then 'x' else 'y'
      'track'
    else
      # Big bag o' states. These use a successor graph to figure out what
      # happens each tick.
      
      # We need to figure out how all the states connect to one another.
      # stateGrid is a map from {dx,dy} to the state's ID.
      stateGrid = {}
      for {dx, dy}, stateid in s.states
        stateGrid["#{dx},#{dy}"] = stateid

      # Because we're a state machine, we have >2 states and can move across the
      # whole plane.
      # up, down, left, right.
      ds = [{dx:0,dy:-1}, {dx:0,dy:1}, {dx:-1,dy:0}, {dx:1,dy:0}]

      for state,stateid in s.states
        # The state's successors map to the 4 directions in ds.
        state.successors = for {dx,dy},i in ds
          stateGrid["#{state.dx+dx},#{state.dy+dy}"] ? stateid

      'statemachine'

    #console.log "Shuttle #{sid} has #{s.states.length} states"
    #console.log s

  makeRegionFrom: (x, y, isTop) ->
    k = "#{x},#{y},#{isTop}"
    rid = @edgeGrid[k]
    return @regions[rid] if rid isnt undefined

    rid = @regions.length
    #console.log "making region #{rid} at #{x}, #{y}, #{isTop}"

    @regions.push r =
      engines: []
      connections: {}
      size: 0
      tempEdges: []
      pressure: 0 # Used mostly for debugging - regions can share engines.
      neutral: true # true if the region is never connected to engines.

    to_explore = []
    visited = {}

    # We'll hit the same engine multiple times. Using a map to dedup, then
    # we'll copy the engines into the region at the end.
    containedEngines = {}

    hmm = (x, y, isTop) =>
      k = "#{x},#{y},#{isTop}"
      if visited[k] is undefined and @edgeGrid[k] is undefined
        #console.log 'expanding', rid, 'to', x, y, isTop
        visited[k] = @edgeGrid[k] = rid
        to_explore.push {x,y,isTop}

    hmm x, y, isTop

    while n = to_explore.shift()
      {x,y,isTop} = n
      #console.log 'expanding', x, y, isTop

      # We need to check for connectivity via the two adjoining grid cells.
      #
      # We need:
      # - x,y of the cell to check
      # - ox,oy is the opposite edge via that cell for when we're calculating
      # bridges.
      # - If we hit a shuttle, we need to know which way the force pushes
      check = if isTop
        # Above, below
        [{x, y:y-1, ox:x, oy:y-1, f:dirs.up}, {x, y, ox:x, oy:y+1, f:dirs.down}]
      else
        # Left, right
        [{x:x-1, y, ox:x-1, oy:y, f:dirs.left}, {x, y, ox:x+1, oy:y, f:dirs.right}]

      for {x,y,ox,oy,f}, i in check
        k = "#{x},#{y}"
        sid = @shuttleGrid[k]
        v = @grid[k]

        #console.log 'flood filling', rid, x, y, f, v
        #@printPoint x, y

        if sid != undefined
          #console.log 'adding temp edge', x, y, sid, f
          #@printPoint x, y
          #console.log '\n'
          # This is the boundary with a shuttle. Mark it - we'll come back in
          # the next pass.
          r.tempEdges.push {x,y,sid,f}

          continue

        # This is a bit of a hack putting this here. We're not going to mark
        # the cell as visited unless its not a shuttle because its important
        # that we visit shuttle cells from every direction (to calculate the
        # force).
        #visited[k] = true

        # This is only advisory (for drawing pressure) - bridges are in 2
        # regions, but we'll just mark one of them.
        @regionGrid[k] = rid if v in ['nothing', 'thinsolid', 'thinshuttle', 'bridge']

        #console.log 'v', x, y, v

        switch v
          when 'bridge'
            r.size++
            hmm ox, oy, isTop
          when 'nothing', 'thinsolid', 'thinshuttle'
            r.size++
            hmm x, y, true
            hmm x, y, false
            hmm x, y+1, true
            hmm x+1, y, false
          when 'positive', 'negative'
            containedEngines[@engineGrid["#{x},#{y}"]] = if v is 'positive' then 1 else -1

    for eid, pressure of containedEngines
      eid = eid|0
      r.engines.push eid
      r.pressure += pressure
      @engines[eid].regions.push rid

    r

  fillRegions: ->
    # Flood fill all the empty regions in the grid
    for k,v of @grid
      {x,y} = parseXY k

      sid = @shuttleGrid[k]
      continue if sid isnt undefined

      # This will happen for all tiles which aren't engines and aren't in shuttle zones
      # (so, engines, empty space, grills and bridges)
      letsAirThrough =
        nothing: yes
        thinsolid: yes
        bridge: yes
        thinshuttle: yes

      # We'll skip making regions when the region is between two engines, or an
      # engine and a wall or something.
      @makeRegionFrom(x+ex, y+ey, isTop) for {ex,ey,isTop,dx,dy} in edges when (
          letsAirThrough[v] ||
          letsAirThrough[@get(x+dx, y+dy)] ||
          @shuttleGrid["#{x+dx},#{y+dy}"] != undefined)

  # Utility method to add a connection from rid1 to rid2 in the given state.
  # You should call this twice (with rid1 and rid2 reversed).
  addConnection: (rid1, rid2, sid, stateid) ->
    r = @regions[rid1]
    numStates = @shuttles[sid].states.length
    c = (r.connections["#{rid2},#{sid}"] ||= {rid:rid2, sid, inStates:new Array(numStates)})
    c.inStates[stateid] = true

  findRegionConnectionsAndShuttleForce: ->
    # Now go through all the regions and figure out the connectivity
    for r,rid in @regions
      for e in r.tempEdges
        {x,y,sid,f} = e
        s = @shuttles[sid]

        if @debug
          console.log "temp edge at region #{rid} shuttle #{sid} (#{x},#{y}) force #{JSON.stringify f}"
          @printPoint x, y

        for state,stateid in s.states
          filledStates = s.fill["#{x},#{y}"]
          #console.log filledStates
          #if @debug then console.log "looking inside for state #{stateid}"
          push = (state.tempPushedBy[rid] ||= {mx:0,my:0})

          #console.log 's', stateid, filledStates
          if filledStates && filledStates[stateid]
            #@printPoint x, y
            
            # Record the force from the touch.
            if @debug then console.log 'outside push', x, y, f
            push.mx += f.dx
            push.my += f.dy
          else
            fill e, (x, y, hmm) =>
              k = "#{x},#{y}"
              return no if @shuttleGrid[k] != sid

              filledStates = s.fill[k]
              return no if filledStates && filledStates[stateid]

              #console.log "state #{stateid} exploring #{x},#{y}"
              #@printPoint x, y

              # Mark that this cell is adjacent to the region in this state.

              # This is used for a couple of things:
              # - When we render the pressure, we need to know which region's
              #   pressure to use in this cell
              # - If multiple regions connect through a cell in a state,
              #   they'll all share the same pressure value. We only want to
              #   push the shuttle once, and we only need to add the regions'
              #   connections once.
              adjList = (s.adjacentTo["#{x},#{y}"] ||= [])
              if adjList[stateid]?
                return no

              if @debug
                console.log "claiming #{x},#{y} in adjacency list with region #{rid}"
              adjList[stateid] = rid

              # Look for connections to other regions. Also figure out if this
              # pressure pushes us.
              for {ex,ey,isTop,dx,dy} in edges
                rid2 = @edgeGrid["#{x+ex},#{y+ey},#{isTop}"]
                if rid2 != undefined && rid2 != rid # && rid2 > rid
                  # Victory
                  #console.log "region #{rid} touches #{rid2} in shuttle #{sid} state #{stateid}"
                  @addConnection rid, rid2, sid, stateid
                  @addConnection rid2, rid, sid, stateid

                # If this shuttle fills the adjacent state, add a force multiplier.
                #console.log "#{x+fx},#{y+fy}", s.fill["#{x+fx},#{y+fy}"]
                if s.fill["#{x+dx},#{y+dy}"]?[stateid]
                  if @debug then console.log 'inside push', x, y, {dx, dy}
                  push.mx += dx
                  push.my += dy

              yes

      delete r.tempEdges

    ###
    if @opts.debug
      for s,sid in @shuttles
        console.log "shuttle #{sid}"
        console.log s.adjacentTo
        for state,stateid in s.states
          util.moveShuttle @grid, @shuttles, sid, s.initial, stateid
          console.log "state #{stateid}"
          util.printCustomGrid @extents, (x, y) =>
            adjList = s.adjacentTo[[x,y]] || []
            adjList[stateid] ? @grid[[x,y]]
          util.moveShuttle @grid, @shuttles, sid, stateid, s.initial

    if @opts.debug
      for s,sid in @shuttles
        console.log 'adj', sid
        console.log s.adjacentTo

      for r,rid in @regions
        console.log 'region', rid
        console.log 'c', c.rid, c.stateid for k,c of r.connections
    ###
    return

  findNeutralRegions: ->
    for e in @engines
      for rid in e.regions
        fillRegions @regions, rid, (rid2, trace) =>
          r = @regions[rid2]
          return no if !r.neutral
          r.neutral = false
          return yes

    if @opts.debug
      console.log "region #{rid} neutral" for r,rid in @regions when r.neutral

  cleanShuttlePush: ->
    # Rewrite shuttle.states[x].tempPushedBy map to shuttle.pushedBy list and
    # shuttle.states[x].pushedBy list.
    for shuttle in @shuttles when !shuttle.immobile
      {x:movesx, y:movesy} = shuttle.moves
      # Same as this, except make sure we end up with a list sorted by rid.
      firstPushedBy = shuttle.states[0].tempPushedBy
      for rid in sortedKeys firstPushedBy when !@regions[rid].neutral
        {mx, my} = firstPushedBy[rid]
        continue unless (mx && movesx) || (my && movesy)
        shared = yes

        for state,stateid in shuttle.states[1...] when shared
          push = state.tempPushedBy[rid]
          
          if push
            shared = no if movesx && push.mx != mx
            shared = no if movesy && push.my != my
          else
            shared = no

        if shared
          pushed = {rid:+rid}
          pushed.mx = mx if movesx
          pushed.my = my if movesy

          shuttle.pushedBy.push pushed

          for state in shuttle.states
            delete state.tempPushedBy[rid]

      # Anything that wasn't shared gets pushed into the state's pushed list.
      for state in shuttle.states
        for rid in sortedKeys state.tempPushedBy when !@regions[rid].neutral
          {mx, my} = state.tempPushedBy[rid]
          pushed = {rid:+rid}
          pushed.mx = mx if movesx
          pushed.my = my if movesy

          if pushed.mx || pushed.my
            state.pushedBy.push pushed

        delete state.tempPushedBy

      #console.log shuttle.pushedBy, (state.pushedBy for state in shuttle.states)

    return

  calculateEngineExclusivity: (e) ->
    # Engines are exclusive if its impossible for a region to be pressurized
    # multiple times from the same engine via multiple paths.
    #
    # Practically, engines are exclusive if they only touch 1 region or if all
    # the regions they touch aren't connected.
    #
    # Most engines are exclusive.
    e.exclusive = true
    return if e.regions.length <= 1

    return e.exclusive = false if !@opts.expensiveOptimizations
    
    # If the engine has multiple regions, it can still be exclusive if the
    # regions are disconnected.
    #
    # This is a pretty expensive check, but its fun. We'll flood fill through
    # the region graph from each of the engine's edges to try and find
    # another edge. If we find ourselves again, we're non-exclusive.
    danger = {}
    danger[rid] = true for rid in e.regions

    # These fills are symmetric, so we only need n-1 of them.
    for rid in e.regions[1...] when e.exclusive
      #console.log 'fill from', rid
      fillRegions @regions, rid, (testRid, trace) =>
        #console.log 'fill', rid, testRid, trace

        if testRid != rid and danger[testRid]
          #console.log "engine #{JSON.stringify e} is non-exclusive!"
          e.exclusive = false
        
        # Continue if we still think we're exclusive.
        return e.exclusive


parse = exports.parse = (grid, opts) ->
  parser = new Parser grid
  parser.parse opts
  parser

parseFile = exports.parseFile = (filename, opts) ->
  fs = require 'fs'
  data = JSON.parse fs.readFileSync(filename, 'utf8').split('\n')[0]
  delete data.tw
  delete data.th

  parse data, opts


# You can invoke this script from the shell and point it at a file. It prints
# out some debugging information.
if require.main == module
  filename = process.argv[2]
  throw Error 'Missing file argument' unless filename
  {shuttles, regions} = data = parseFile filename, debug:true

  for s,sid in shuttles
    console.log "shuttle #{sid} (#{s.type}):"
    console.log 'pushedby', s.pushedBy
    console.log state for state in s.states

  console.log()
  for r,rid in regions
    console.log "region #{rid}"
    console.log r
    console.log c for k,c of r.connections

  graphFile = filename.split('.')[0] + '.svg'
  util.drawRegionGraph data, graphFile

