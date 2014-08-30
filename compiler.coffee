util = require 'util'

Heap = require 'heap'

cardinal_dirs = [[0,1],[0,-1],[1,0],[-1,0]]

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
  {dx:0,dy:0,isTop:false}
  {dx:0,dy:0,isTop:true}
  {dx:1,dy:0,isTop:false}
  {dx:0,dy:1,isTop:true}
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

      check = if isTop
        [{x, y:y-1, ox:x, oy:y-1}, {x, y, ox:x, oy:y+1}]
      else
        [{x:x-1, y, ox:x-1, oy:y}, {x, y, ox:x+1, oy:y}]

      for {x,y,ox,oy}, i in check
        k = "#{x},#{y}"
        continue if visited[k]
        visited[k] = true
        a = @annotatedGrid[k]
        v = @grid[k]

        if v not in ['positive','negative'] and a != undefined
          # This is the boundary with a shuttle. Mark it - we'll come back in
          # the next pass.
          r.tempEdges.push {x,y,a}
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
            r.engines[@annotatedGrid["#{x},#{y}"]] = if v is 'positive' then 1 else -1

    r

  compile: ->
    @print()
    # map from grid position -> ID of thing
    @annotatedGrid = {}

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
          @annotatedGrid["#{x},#{y}"] = id

        when 'shuttle', 'thinshuttle'
          # flood fill the shuttle extents.
          continue if @annotatedGrid["#{x},#{y}"]?

          immobile = v is 'thinshuttle'
          id = @shuttles.length
          @shuttles.push s =
            points: [] # List of points in the shuttle in the base state
            fill: {} # Map from x,y -> [true if filled in state=index]
            states: [] # List of the {dx,dy} of each state
            adjacentTo: {} # Map from {x,y} -> [region id]

          # Flood fill the shuttle
          fill {x,y}, (x, y) =>
            if @get(x, y) in ['shuttle', 'thinshuttle']
              immobile = false if immobile && @get(x,y) is 'shuttle'

              @annotatedGrid["#{x},#{y}"] = id
              s.points.push {x,y}
              true
            else
              false
          s.immobile = immobile

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
        s.states.push {dx, dy}
        # Ok, this state is legit. Mark the filled cells as impassable in this
        # state.
        for {x,y} in s.points when @get(x, y) is 'shuttle'
          _x = x+dx; _y = y+dy
          currentAnnotation = @annotatedGrid[[_x, _y]]
          if currentAnnotation? and currentAnnotation != id
            throw Error 'Potentially overlapping shuttles'

          @annotatedGrid[[_x, _y]] = id

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

      id = @annotatedGrid[k]
      continue if id isnt undefined and v not in ['positive', 'negative']

      # This will happen for all tiles which aren't engines and aren't in shuttle zones
      # (so, engines, empty space, grills and bridges)
      for {dx,dy,isTop} in edges
        @makeRegionAt x+dx, y+dy, isTop

    @print()
    @printEdges()


    # Now go through all the regions and figure out the connectivity
    for r,rid in @regions
      for e in r.tempEdges
        {x,y,a} = e
        s = @shuttles[a]
        #console.log x,y,s
        filledStates = s.fill["#{x},#{y}"]
        #console.log filledStates

        for state in [0...s.numStates] when !filledStates || !filledStates[state]
          fill e, (x, y, hmm) =>
            k = "#{x},#{y}"
            return no if @annotatedGrid[k] != a

            filledStates = s.fill[k]
            return no if filledStates && filledStates[state]

            adjList = (s.adjacentTo["#{x},#{y}"] ||= [])
            adjList[state] ?= rid

            # Look for connections to other regions
            for {dx,dy,isTop} in edges
              rid2 = @edgeGrid["#{x+dx},#{y+dy},#{isTop}"]
              if rid2 != undefined && rid2 != rid && rid2 > rid
                # Victory
                console.log "region #{rid} touches #{rid2} in shuttle #{a} state #{state}"

                r2 = @regions[rid2]
                # No idea what the most convenient representation of this data is yet.
                r.connections[[rid2,a,state]] = {r:rid2, shuttle:a, state}
                r2.connections[[rid,a,state]] = {r:rid, shuttle:a, state}

            yes

      delete r.tempEdges

      if numKeys(r.connections)
        console.log "#{rid}:"
        console.log JSON.stringify r, null, 2

    console.log JSON.stringify @shuttles, null, 2

    @drawRegionGraph "out.dot"


    for y in [@top..@bottom]
      for x in [@left..@right]
        process.stdout.write "#{@annotatedGrid[[x,y]] ? '.'}"
      process.stdout.write '\n'

    return
    













    # Ok, we've blocked out the shuttle zones. Flood fill pressurized space
    regions = []
    
    # Conditional pressure in every cell.
    # Maps [x,y] -> [list of ORs], each is {shuttle id: [true, false, ...]} ANDs
    pressure = {}

    for k,p of engines
      pressure = if @get(p.x, p.y) is 'positive' then 1 else -1
      console.log "engine #{pressure} at", p
      
      queue = new Heap (a, b) ->
        return 0 if a == b
        numKeys(a.data) - numKeys(b.data)

      tempGrid = {}

      fill2 p, {}, queue, (x, y, allowedShuttleStates, prevStates, hmm) =>
        return allowedShuttleStates if x == p.x and y == p.y

        cell = @get x, y
        shuttleId = annotatedGrid[[x,y]]
        shuttle = if shuttleId? then shuttles[shuttleId]

        if !shuttle || (shuttle && shuttle.immobile)
          if cell in ['nothing', 'thinsolid', 'thinshuttle']
            tempGrid[[x,y]] = '+'
            return allowedShuttleStates
          else
            tempGrid[[x,y]] = ','
            return no

        #console.log x, y, allowedShuttleStates, @get(x, y), annotatedGrid[[x,y]]

        throw 'blah' if shuttleId >= shuttles.length
        #console.log 'hit shuttle', shuttleId


        # The air can only pass if the shuttle is in one of the states not in
        # filledInState.
        #console.log x, y, 's', shuttle
        filledInStates = shuttle.fill[[x,y]]

        #console.log filledInStates

        # We might already be conditioned on some state(s).
        alreadyAllowed = allowedShuttleStates[shuttleId]

        # Check that we haven't exhausted all the state space.
        exhausted = yes

        allowedStates = for i in [0...shuttle.numStates]
          #console.log i, filledInStates, alreadyAllowed
          if (!filledInStates || !filledInStates[i]) && (!alreadyAllowed || alreadyAllowed[i])
            exhausted = no
            yes
          else
            no

        if exhausted
          tempGrid[[x,y]] = '#'
          return no

        #console.log 'a', allowedStates

        # Shallow clone of allowedShuttleStates.
        newData = {}
        newData[id] = s for id, s of allowedShuttleStates
        newData[shuttleId] = allowedStates

        console.log 'yes', x, y, newData
        #newData
        tempGrid[[x,y]] = 'x'
        newData

      for y in [@top..@bottom]
        for x in [@left..@right]
          process.stdout.write "#{tempGrid[[x,y]] ? '.'}"
        process.stdout.write '\n'
      

  

      ###
      cell = @get x, y
      cell = 'nothing' if x is v.x and y is v.y
      if cell in ['nothing', 'thinshuttle', 'thinsolid']
        pressure["#{x},#{y}"] = (pressure["#{x},#{y}"] ? 0) + direction

        # Propogate pressure through bridges
        for [dx,dy] in cardinal_dirs
          _x = x + dx; _y = y + dy

          if @get(_x, _y) is 'bridge'
            while (c = @get _x, _y) is 'bridge'
              pressure["#{_x},#{_y}"] = (pressure["#{_x},#{_y}"] ? 0) + direction
              _x += dx; _y += dy
            
            if c in ['nothing', 'thinshuttle', 'thinsolid']
              hmm _x, _y

        return true
      false
      ###







    console.log annotatedGrid
    #console.log JSON.stringify shuttles, null, 2




#filename = 'almostEmpty.json'
#filename = 'and-or2.json'
filename = 'cpu.json'
#filename = 'oscillator.json'
#filename = 'fork.json'



compile = (world) ->
  new Compiler(world).compile()

if require.main == module
  fs = require 'fs'
  data = JSON.parse fs.readFileSync(filename, 'utf8').split('\n')[0]

  c = new Compiler data
  c.compile()

