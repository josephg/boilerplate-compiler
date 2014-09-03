{parseXY, numKeys, fill, fillRegions, gridExtents, printGrid, printPoint, printEdges} = require './util'

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


    # This is our final output - a list of shuttles and regions which mutually affect one another.
    @shuttles = []
    @regions = []
    # The engine list is important for figuring out which regions share each
    # engine. Usually none will - but its part of the spec that they can.
    @engines = []

  # **** Helper functions
  get: (x,y) -> @grid["#{x},#{y}"]

  parse: (@opts = {}) ->
    # For now.
    @opts.expensiveOptimizations = true

    # The drawing functions are the only thing that uses this.
    if @opts.debug
      @extents = gridExtents @grid
      printGrid @extents, @grid

    # Annotate the grid, marking engines and shuttles (in their current position)
    @annotateGrid()
    
    # Figure out all the places shuttles can move to, filling a cloud in the shuttle grid.
    @findShuttleStates()

    # Ok, now calculate all the successor states for each shuttle state.
    @findSuccessorStates s for s in @shuttles

    # Find & fill all regions in the edge grid.
    @fillRegions()

    # For each region, figure out which other regions it can connect to and
    # which shuttles it pushes.
    @findRegionConnectionsAndShuttleForce()

    # Trim pushedBy values in shuttles
    @cleanShuttlePush()

    # Figure out which engines (if any) are important in by multiple regions.
    @calculateEngineExclusivity e for e in @engines

    if @opts.debug
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
            points: [] # List of points in the shuttle in the base state
            fill: {} # Map from x,y -> [true if filled in state=index]
            stateGrid: {}
            states: [] # List of the {dx,dy,pushedBy} of each state
            adjacentTo: {} # Map from {x,y} -> [region id]
            moves: {x:false, y:false}
            immobile: v is 'thinshuttle' # Immobile if only thinshuttle, no states or no pressure possible.
            pushedBy: [] # List of {rid, mx, my} across all states

          # Flood fill the shuttle
          fill {x,y}, (x, y) =>
            if @get(x, y) in ['shuttle', 'thinshuttle']
              s.immobile = false if s.immobile && @get(x,y) is 'shuttle'

              @shuttleGrid["#{x},#{y}"] = id
              s.points.push {x,y}
              true
            else
              false

  findShuttleStates: ->
    # For each shuttle, figure out where it can move to.
    for s,id in @shuttles when !s.immobile
      # Find all the states.
      fill {x:0, y:0}, (dx, dy) =>
        # x, y is an offset for the shuttle. Figure out if its viable.
        #
        # We'll assume that any shuttles are either part of the current
        # shuttle, or they'll move out of the way before we get there.
        for {x,y} in s.points
          if @get(x+dx, y+dy) not in ['nothing', 'shuttle', 'thinshuttle']
            return false
  
        stateid = s.states.length
        # pushedBy is a list of {rid,mx,my} multipliers
        s.states.push {dx, dy, pushedBy:[], tempPushedBy:{}, successors:[]}
        s.stateGrid["#{dx},#{dy}"] = stateid

        s.moves.x = true if dx
        s.moves.y = true if dy

        # Ok, this state is legit. Mark the filled cells as impassable in this
        # state.
        for {x,y} in s.points when @get(x, y) is 'shuttle'
          _x = x+dx; _y = y+dy
          currentShuttle = @shuttleGrid[[_x, _y]]
          if currentShuttle? and currentShuttle != id
            throw Error 'Potentially overlapping shuttles'

          @shuttleGrid[[_x, _y]] = id

          f = (s.fill[[_x, _y]] ?= [])
          f[stateid] = true
          #f.push state

        #console.log 'it could move to ', dx, dy
        return true

      s.immobile = true if s.states.length is 1


      #console.log "Shuttle #{id} has #{numStates} states"
      #console.log s

  findSuccessorStates: (s) ->
    return if s.immobile

    if s.moves.x && s.moves.y
      # up, right, down, left.
      ds = [{dx:0,dy:-1}, {dx:1,dy:0}, {dx:0,dy:1}, {dx:-1,dy:0}]
    else if s.moves.x
      ds = [{dx:-1,dy:0}, {dx:1,dy:0}]
    else if s.moves.y
      ds = [{dx:0,dy:-1}, {dx:0,dy:1}]
    else
      return

    #console.log s.stateGrid
    for state,sid in s.states
      for {dx,dy},i in ds
        successor = s.stateGrid["#{state.dx+dx},#{state.dy+dy}"]
        state.successors[i] = successor ? sid

      code = state.successors.join ' '
      if sid is 0
        globalSuccessors = code
      else if globalSuccessors
        globalSuccessors = null if globalSuccessors != code

    if globalSuccessors
      # All the successor lists are the same! Hoist!
      s.successors = s.states[0].successors
      for state in s.states
        delete state.successors

  makeRegionFrom: (x, y, isTop) ->
    k = "#{x},#{y},#{isTop}"
    id = @edgeGrid[k]
    return @regions[id] if id isnt undefined

    #console.log "making region at #{x}, #{y}, #{isTop}"

    id = @regions.length
    @regions.push r =
      engines: []
      connections: {}
      size: 0
      tempEdges: []
      pressure: 0 # Used mostly for debugging - regions can share engines.

    to_explore = []
    visited = {}

    # We'll hit the same engine multiple times. Using a map to dedup, then
    # we'll copy the engines into the region at the end.
    containedEngines = {}

    hmm = (x, y, isTop) =>
      k = "#{x},#{y},#{isTop}"
      if @edgeGrid[k] is undefined
        #console.log 'expanding', id, 'to', x, y, isTop
        @edgeGrid[k] = id
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
        continue if visited[k]
        visited[k] = true
        sid = @shuttleGrid[k]
        v = @grid[k]

        #console.log 'flood filling', id, x, y, f
        #@printPoint x, y

        if sid != undefined
          #console.log 'adding temp edge', x, y, a, f
          #console.log '\n'
          # This is the boundary with a shuttle. Mark it - we'll come back in
          # the next pass.
          r.tempEdges.push {x,y,sid,f}
          continue

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
      @engines[eid].regions.push id

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


  findRegionConnectionsAndShuttleForce: ->
    # Now go through all the regions and figure out the connectivity
    for r,rid in @regions
      for e in r.tempEdges
        {x,y,sid,f} = e
        s = @shuttles[sid]
        #console.log "temp edge at region #{rid} shuttle #{sid} (#{x},#{y}) force #{JSON.stringify f}"
        #@printPoint x, y

        for state,stateid in s.states
          filledStates = s.fill["#{x},#{y}"]
          #console.log filledStates
          #console.log "looking inside for state #{stateid}"
          push = (state.tempPushedBy[rid] ||= {mx:0,my:0})

          #console.log 's', stateid, filledStates
          if filledStates && filledStates[stateid]
            #@printPoint x, y
            
            # Record the force from the touch.
            push.mx += f.dx
            push.my += f.dy
          else
            fill e, (x, y, hmm) =>
              k = "#{x},#{y}"
              return no if @shuttleGrid[k] != sid

              filledStates = s.fill[k]
              return no if filledStates && filledStates[stateid]

              # Mark that this cell is adjacent to the region in this state.
              # This is a helper for when we render the pressure.
              adjList = (s.adjacentTo["#{x},#{y}"] ||= [])
              adjList[stateid] ?= rid

              # Look for connections to other regions. Also figure out if this
              # pressure pushes us.
              for {ex,ey,isTop,dx,dy} in edges
                rid2 = @edgeGrid["#{x+ex},#{y+ey},#{isTop}"]
                if rid2 != undefined && rid2 != rid && rid2 > rid
                  # Victory
                  #console.log "region #{rid} touches #{rid2} in shuttle #{sid} state #{stateid}"

                  r2 = @regions[rid2]
                  # No idea what the most convenient representation of this data is yet.
                  r.connections[[rid2,sid,stateid]] = {rid:rid2, sid, stateid}
                  r2.connections[[rid,sid,stateid]] = {rid:rid, sid, stateid}

                # If this shuttle fills the adjacent state, add a force multiplier.
                #console.log "#{x+fx},#{y+fy}", s.fill["#{x+fx},#{y+fy}"]
                if s.fill["#{x+dx},#{y+dy}"]?[stateid]
                  push.mx += dx
                  push.my += dy

              yes

      delete r.tempEdges


  cleanShuttlePush: ->
    # Rewrite shuttle.states[x].tempPushedBy map to shuttle.pushedBy list and
    # shuttle.states[x].pushedBy list.
    for shuttle in @shuttles
      {x:movesx, y:movesy} = shuttle.moves
      for rid, {mx,my} of shuttle.states[0].tempPushedBy when (mx && movesx) || (my && movesy)
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
        for rid, {mx, my} of state.tempPushedBy
          pushed = {rid:+rid}
          pushed.mx = mx if movesx
          pushed.my = my if movesy

          if pushed.mx || pushed.my
            state.pushedBy.push pushed

        delete state.tempPushedBy


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
      fillRegions @regions, rid, (testRid, trace) =>
        #console.log rid, testRid, trace.path

        if testRid != rid and danger[testRid]
          #console.log "engine #{e} is non-exclusive!"
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



#filename = 'almostEmpty.json'
filename = 'and-or2.json'
#filename = 'cpu.json'
#filename = 'oscillator.json'
#filename = 'exclusive.json'
#filename = 'fork.json'
#filename = '4spin.json'
#filename = 'test.json'

if require.main == module
  {shuttles, regions} = parseFile filename, debug:true

  console.log s.successors, s.states for s in shuttles

