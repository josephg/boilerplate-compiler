
chars =
  positive: '+'
  negative: '-'
  nothing: ' '
  thinsolid: 'x'
  shuttle: 'S'
  thinshuttle: 's'
  bridge: 'b'

parseXY = exports.parseXY = (k) ->
  [x,y] = k.split ','
  {x:x|0, y:y|0}

numKeys = exports.numKeys = (obj) ->
  num = 0
  num++ for k of obj
  num

# Flood fill through the grid from a cell
exports.fill = (initial_square, f) ->
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

# Flood fill through the graph of connected regions. DFS for now - assuming
# there's no path between regions thats bigger than the node stack.
exports.fillRegions = (regions, initialRid, f) ->
  expand = (rid, trace) =>
    region = regions[rid]

    shouldExpand = f rid, trace
    return unless shouldExpand

    for k,{rid:nextRid,sid,stateid} of region.connections
      continue if nextRid in trace.path

      currentState = trace.shuttleState[sid]

      if currentState == undefined
        set = true
        trace.shuttleState[sid] = stateid
      else if currentState != stateid
        # Mutually exclusive states - skip.
        continue
      else
        set = false

      trace.path.push nextRid

      expand nextRid, trace

      trace.path.pop()
      delete trace.shuttleState[sid] if set

  expand initialRid, {path:[initialRid], shuttleState:{}}

exports.gridExtents = (grid) ->
  # calculate the extents
  top = left = bottom = right = null

  for k, v of grid
    {x,y} = parseXY k
    left = x if left is null || x < left
    right = x if right is null || x > right
    top = y if top is null || y < top
    bottom = y if bottom is null || y > bottom

  {top, left, bottom, right}


exports.printGrid = ({top, left, bottom, right}, grid, stream = process.stdout) ->
  for y in [top-1..bottom+1]
    stream.write ''
    for x in [left-1..right+1]
      stream.write chars[grid[[x, y]]] || ';'
    stream.write '\n'

exports.printPoint = ({top, left, bottom, right}, grid, px, py) ->
  for y in [top-1..bottom+1]
    process.stdout.write ''
    for x in [left-1..right+1]
      process.stdout.write(
        if x == px and y == py
          '%'
        else
          chars[grid[[x, y]]] || ';'
      )
    process.stdout.write '\n'

exports.printEdges = ({top, left, bottom, right}, grid, edgeGrid, stream = process.stdout) ->
  edgeChar = (x, y, isTop) ->
    e = edgeGrid["#{x},#{y},#{isTop}"]
    if e?
      e % 10
    else
      ' '

  for y in [top..bottom+1]
    # tops
    for x in [left..right]
      stream.write " #{edgeChar x, y, true}"
    stream.write '\n'
    # lefts
    if y <= bottom
      for x in [left..right+1]
        stream.write "#{edgeChar x, y, false}"
        if x <= right
          stream.write chars[grid[[x, y]]] || ';'
      stream.write '\n'
  stream.write '\n'


exports.drawRegionGraph = (parserData, filename) ->
  {shuttles, regions} = parserData
  console.log '\n\n\n'
  g = require('graphviz').graph 'regions'

  for r,rid in regions when numKeys r.connections
    color = undefined
    name = "#{rid}"
    if r.pressure > 0
      name += "(+#{r.pressure})"
      color = 'green'
    else if r.pressure < 0
      name += "(#{r.pressure})"
      color = 'red'

    r.graphName = name
    node = g.addNode name, {shape:'box', color}

  for s,sid in shuttles
    g.addNode "S#{sid}", {shape:'oval', style:'filled', fillcolor:'plum1'}

  for r,rid in regions when numKeys r.connections
    for k,c of r.connections when c.rid > rid
      edge = g.addEdge r.graphName, regions[c.rid].graphName
      edge.set 'label', "S#{c.sid} s#{c.stateid}"

    if r.dependants
      for d in r.dependants
        g.addEdge r.graphName, "S#{d}"

  #console.log g.to_dot()
  g.output filename.split('.')[1], filename
  console.log "generated #{filename}"


