util = require 'util'

Heap = require 'heap'


dirs =
  up: {dx:0,dy:-1}
  right: {dx:1,dy:0}
  down: {dx:0,dy:1}
  left: {dx:-1,dy:0}

fill = (initial_square, f) ->
  visited = {}
  visited["#{initial_square.x},#{initial_square.y}"] = true
  to_explore = [initial_square]
  hmm = (x,y) ->
    k = "#{x},#{y}"
    if not visited[k]
      visited[k] = true
      to_explore.push {x,y}
  while n = to_explore.shift()
    ok = f n.x, n.y, hmm
    if ok
      hmm n.x+1, n.y
      hmm n.x-1, n.y
      hmm n.x, n.y+1
      hmm n.x, n.y-1
  return


edges = [
  {ex:0,ey:0,isTop:false,dx:-1,dy:0}
  {ex:0,ey:0,isTop:true,dx:0,dy:-1}
  {ex:1,ey:0,isTop:false,dx:1,dy:0}
  {ex:0,ey:1,isTop:true,dx:0,dy:1}
]
 
chars =
  positive: '+'
  negative: '-'
  nothing: ' '
  thinsolid: 'x'
  shuttle: 'S'
  thinshuttle: 's'
  bridge: 'b'

fill2 = (p, initial_data, queue, f) ->
  visited = {}
  #visited["#{p.x},#{p.y}"] = initial_data
  queue.push {p, data:initial_data}
  hmm = (data, x, y) ->
    k = "#{x},#{y}"
    #if not visited[k]
    visited[k] = data
    queue.push {p:{x,y}, data}

  while n = queue.pop()
    #console.log 'popped', n
    p = n.p
    newData = f p.x, p.y, n.data, visited["#{p.x},#{p.y}"], hmm
    if newData
      hmm newData, p.x+1, p.y
      hmm newData, p.x-1, p.y
      hmm newData, p.x, p.y+1
      hmm newData, p.x, p.y-1
  return


parseXY = (k) ->
  [x,y] = k.split ','
  {x:x|0, y:y|0}

numKeys = (obj) ->
  num = 0
  num++ for k of obj
  num


# This is just a function, damnit.
class Compiler
  constructor: (grid) ->
    #nextId = 1
    @setGrid grid

  setGrid: (grid) ->
    @grid = grid || {}

    # calculate the extents
    @top = @left = @bottom = @right = null

    for k, v of @grid
      {x,y} = parseXY k
      @left = x if @left is null || x < @left
      @right = x if @right is null || x > @right
      @top = y if @top is null || y < @top
      @bottom = y if @bottom is null || y > @bottom

  get: (x,y) -> @grid["#{x},#{y}"]

  print: ->
    #console.log top, right, left, bottom
   
    for y in [@top-1..@bottom+1]
      process.stdout.write ''
      for x in [@left-1..@right+1]
        process.stdout.write chars[@get x, y] || ';'
      process.stdout.write '\n'


  printPoint: (px, py)->
    #console.log top, right, left, bottom
   
    for y in [@top-1..@bottom+1]
      process.stdout.write ''
      for x in [@left-1..@right+1]
        process.stdout.write(
          if x == px and y == py
            '%'
          else
            chars[@get x, y] || ';'
        )
      process.stdout.write '\n'


  printEdges: ->
    for y in [@top..@bottom+1]
      # tops
      for x in [@left..@right]
        process.stdout.write " #{@edgeGrid[[x,y,true]] ? ' '}"
      process.stdout.write '\n'
      # lefts
      if y <= @bottom
        for x in [@left..@right+1]
          process.stdout.write "#{@edgeGrid[[x,y,false]] ? ' '}"
          if x <= @right
            process.stdout.write chars[@get x, y] || ';'
        process.stdout.write '\n'
    process.stdout.write '\n'

  drawRegionGraph: (filename) ->
    console.log '\n\n\n'
    g = require('graphviz').graph 'regions'

    for r,rid in @regions when numKeys r.connections
      strength = 0
      for k, v of r.engines
        strength += v

      color = undefined
      name = "#{rid}"
      if strength > 0
        name += "(+#{strength})"
        color = 'green'
      else if strength < 0
        name += "(#{strength})"
        color = 'red'

      r.graphName = name
      node = g.addNode name, {color}

    for r,rid in @regions when numKeys r.connections
      for k,c of r.connections when c.r > rid
        edge = g.addEdge r.graphName, @regions[c.r].graphName
        edge.set 'label', "S#{c.shuttle} s#{c.state}"

    console.log g.to_dot()
    g.output 'svg', "#{filename}.svg"
    

  #id: -> nextId++
 
  makeRegionAt: (x, y, isTop) ->
    k = "#{x},#{y},#{isTop}"
    id = @edgeGrid[k]
    return @regions[id] if id isnt undefined

    #console.log "making region at #{x}, #{y}, #{isTop}"

    id = @regions.length
    @regions.push r =
      engines: {}
      connections: {}
      size: 0
      tempEdges: []

    to_explore = []
    visited = {}

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
            r.engines[@engineGrid["#{x},#{y}"]] = if v is 'positive' then 1 else -1

    r

  compile: ->
    @print()
    # map from grid position -> ID of shuttle
    @shuttleGrid = {}
    # map from grid position -> ID of engine
    @engineGrid = {}

    @shuttles = []
    @engines = []

    @regions = []

    @edgeGrid = {}

    # Find and mark all the current shuttles & engines
    for k,v of @grid when k not in ['tw', 'th']
      {x,y} = parseXY k
      switch v
        when 'positive', 'negative'
          # Mark these - we'll need them later.
          id = @engines.length
          @engines.push {x,y}
          @engineGrid["#{x},#{y}"] = id

        when 'shuttle', 'thinshuttle'
          # flood fill the shuttle extents.
          continue if @shuttleGrid["#{x},#{y}"]?

          id = @shuttles.length
          @shuttles.push s =
            points: [] # List of points in the shuttle in the base state
            fill: {} # Map from x,y -> [true if filled in state=index]
            states: [] # List of the {dx,dy,pushedBy} of each state
            adjacentTo: {} # Map from {x,y} -> [region id]
            moves: {x:false, y:false}
            immobile: v is 'thinshuttle' # Immobile if only thinshuttle, no states or no pressure possible.
            pushedBy: {} # Map from rid -> force across all states

          # Flood fill the shuttle
          fill {x,y}, (x, y) =>
            if @get(x, y) in ['shuttle', 'thinshuttle']
              s.immobile = false if s.immobile && @get(x,y) is 'shuttle'

              @shuttleGrid["#{x},#{y}"] = id
              s.points.push {x,y}
              true
            else
              false

    # For each shuttle, figure out where it can move to.
    for s,id in @shuttles when !s.immobile
      numStates = 0

      fill {x:0, y:0}, (dx, dy) =>
        # x, y is an offset for the shuttle. Figure out if its viable.
        #
        # We'll assume that any shuttles are either part of the current
        # shuttle, or they'll move out of the way before we get there.
        for {x,y} in s.points
          if @get(x+dx, y+dy) not in ['nothing', 'shuttle', 'thinshuttle']
            return false
  
        state = numStates++
        s.states.push {dx, dy, pushedBy:{}} # pushedBy is a map from rid -> {mx,my} multipliers

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
          f[state] = true
          #f.push state

        #console.log 'it could move to ', dx, dy
        return true

      s.numStates = numStates
      s.immobile = true if numStates is 1

      console.log "Shuttle #{id} has #{numStates} states"
      #console.log s
      

    # Flood fill all the empty regions in the grid
    for k,v of @grid when k not in ['tw', 'th']
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
      @makeRegionAt(x+ex, y+ey, isTop) for {ex,ey,isTop,dx,dy} in edges when (
          letsAirThrough[v] ||
          letsAirThrough[@get(x+dx, y+dy)] ||
          @shuttleGrid["#{x+dx},#{y+dy}"] != undefined)

    @print()
    @printEdges()


    # Now go through all the regions and figure out the connectivity
    for r,rid in @regions
      for e in r.tempEdges
        {x,y,sid,f} = e
        s = @shuttles[sid]
        console.log "temp edge at region #{rid} shuttle #{sid} (#{x},#{y}) force #{JSON.stringify f}"
        #@printPoint x, y

        for state,stateid in s.states
          filledStates = s.fill["#{x},#{y}"]
          #console.log filledStates
          console.log "looking inside for state #{stateid}"
          push = (state.pushedBy[rid] ||= {mx:0,my:0})

          console.log 's', stateid, filledStates
          if !filledStates || !filledStates[stateid]
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
                  console.log "region #{rid} touches #{rid2} in shuttle #{sid} state #{stateid}"

                  r2 = @regions[rid2]
                  # No idea what the most convenient representation of this data is yet.
                  r.connections[[rid2,sid,stateid]] = {r:rid2, shuttle:sid, state:stateid}
                  r2.connections[[rid,sid,stateid]] = {r:rid, shuttle:sid, state:stateid}

                # If this shuttle fills the adjacent state, add a force multiplier.
                #console.log "#{x+fx},#{y+fy}", s.fill["#{x+fx},#{y+fy}"]
                if s.fill["#{x+dx},#{y+dy}"]?[stateid]
                  push.mx += f.dx
                  push.my += f.dy

              yes
          else
            console.log 'state filled', x, y, rid, stateid
            #@printPoint x, y
            # Record the force from the touch.
            push.mx += f.dx
            push.my += f.dy

      delete r.tempEdges

      if numKeys(r.connections)
        console.log "#{rid}:"
        console.log JSON.stringify r, null, 2


    # Now simplify the shuttles a little. Hoist pushedBy 
    for shuttle in @shuttles
      for rid, {mx,my} of shuttle.states[0].pushedBy
        shared = yes
        for state in shuttle.states[1...]
          shared = no if shuttle.moves.x && state.pushedBy[rid].mx != mx
          shared = no if shuttle.moves.y && state.pushedBy[rid].my != my

          delete state.pushedBy[rid].mx if !shuttle.moves.x
          delete state.pushedBy[rid].my if !shuttle.moves.y

        if shared
          pushed = {}
          pushed.mx = mx if shuttle.moves.x
          pushed.my = my if shuttle.moves.y

          if pushed.mx || pushed.my
            shuttle.pushedBy[rid] = pushed

          for state in shuttle.states
            delete state.pushedBy[rid]


    console.log JSON.stringify @shuttles, null, 2

    @drawRegionGraph "out.dot"


    for y in [@top..@bottom]
      for x in [@left..@right]
        process.stdout.write "#{@shuttleGrid[[x,y]] ? @engineGrid[[x,y]] ? '.'}"
      process.stdout.write '\n'

    return


#filename = 'almostEmpty.json'
#filename = 'and-or2.json'
#filename = 'cpu.json'
#filename = 'oscillator.json'
#filename = 'fork.json'
filename = '4spin.json'
#filename = 'test.json'



compile = (world) ->
  new Compiler(world).compile()

if require.main == module
  fs = require 'fs'
  data = JSON.parse fs.readFileSync(filename, 'utf8').split('\n')[0]

  c = new Compiler data
  c.compile()

