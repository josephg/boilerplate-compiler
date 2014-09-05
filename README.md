# Boilerplate Compiler

This is a compiler for [boilerplate](https://github.com/josephg/boilerplate). It has two parts:

- [Parser](parser.coffee) takes a boilerplate program (grid) and produces an AST. (Well, its a graph not a tree. ASG?)
- [js-codegen](js-codegen.coffee) takes a parsed boilerplate program and produces javascript which can be run to figure out what will happen.

Caveats:

- The compiler won't compile boilerplate worlds where two shuttles could move
into the same cell. (Even if they won't ever actually do that!)
- The compiled output has a super primitive API. I need to add helper functions
for querying pressure.
- No support for buttons.

# Usage

```
npm install boilerplate-compiler
```

Then compile something:

```javascript
compiler = require('boilerplate-compiler');

// Compile the grid in "myfile.json"
compiler.compileFile("myfile.json", opts);

// Compile the specified grid
var grid = {"0,0":"shuttle","1,0":"nothing","2,0":"negative"};
compiler.compileGrid(grid, opts);
```

Options is optional, and can contain:

- **stream**: The stream to compile to. Compilation is syncronous, but stream
writes can be asyncronous. If not specified, the compiler will output to
process.stdout.
- **fillMode**: One of 'all', 'shuttles', 'engines'. Specifies where the
generated code fills pressure from. Defaults to either shuttles or engines,
whichever is smaller. If you need to know the pressure in all regions (instead
of just the regions which push shuttles), you should explicitly set fillMode to
'engines'.
- **module**: One of 'bare', 'node' or 'fn'. Defaults to 'node'.
  - 'bare' mode creates a function body.
  - 'node' creates a nodejs module.
  - 'fn' creates a self calling closure-wrapped function.


## Compiler output

The compiler output produces a module which returns an object with
`{states:[0,1,3,1,...], step:function(){...})}`. The states array is
initialized with all shuttles in the positions specified in the initial grid.
The step function reads from & writes back new states to the state array.

Internally, the compiled code calculates the pressure of lots of regions.
However, it doesn't expose these values yet.


## Parser output

The parser produces a (somewhat giant) structure of data through the course of
analysing the grid. The format of this structure is still in flux, and it may
change between compiler minor versions.

You can parse data using:

```javascript
compiler = require('boilerplate-compiler');

// parse the grid in "myfile.json"
var ast = compiler.parseFile("myfile.json");

// Compile the specified grid
var grid = {"0,0":"shuttle","1,0":"nothing","2,0":"negative"};
var ast = compiler.parse(grid);
```


At a glance, it contains:

- **grid**: The original grid.
- **shuttles**: A list of shuttles.
- **regions**: A list of regions in the grid.
- **engines**: A list of engines
- **shuttleGrid**: A grid which maps x,y to the ID (index) of a shuttle.
- **engineGrid**: A grid which maps x,y to the ID (index) of an engine.
- **edgeGrid**: A grid mapping x,y,isTop to the ID of the contained region.


### Shuttles

Each shuttle is flood filled to find all the cells the shuttle could occupy. We
do this even if its impossible for the shuttle to actually move there (there's
no engines, for example). The result is that part of the grid is occupied by a
sort of probability cloud of the shuttle's states.

Each state that the shuttle could move to is numbered from 0. States are always
sorted top-to-bottom then left-to-right.

The parser outputs the shuttle list as:

- **points**: List of points `{x:x,y:y,v:value (shuttle/thinshuttle)}` in the
shuttle in its initial position
- **immobile**: Bool, true if the shuttle can't move.
- **type**: The shuttle's type. One of:
  - **immobile**: The shuttle can't move
  - **switch**: The shuttle has exactly 2 states. The top/left state is state
  0, and the bottom/right state is state 1.
  - **track**: The shuttle moves along 1 axis (x or y). States are numbered
  from 0 (most left / top state) along the track.
  - **statemachine**: The shuttle can move in a complicated xy region. This
  is the fallback. Each state stores a list of successors corresponding to
  the state index if the shuttle moves up, down, left, right respectively.
- **states**: List of all the places the shuttle can move to. Each state has
`{dx, dy, pushedBy}`. dx/dy specify how the shuttle has moved from the base
state. `pushedBy` is a list of regions which push the shuttle in this state.
- **initial**: The ID of the starting state (where the shuttle is in the initial grid)
- **fill**: Maps `x,y` to a state list. Each list value is truthy if that cell is
impassable in the state corresponding to the list index.
- **adjacentTo**: Maps `x,y` to a state list. Each list value specifies the
index of a region which connects through this grid cell.
- **moves**: `{x,y}` specifying which directions the shuttle can move. Eg,
`{x:true, y:false}`.
- **pushedBy**: List of `{rid, mx, my}` for each region which pushes the
shuttle consistently in all shuttle states.


### Regions

The space is flood filled from the edges of each cell to find regions. Each
region is a set of edges which always share the same pressure value. Regions
cannot touch each other directly (then they should be joined!).

Regions have a list of *connections* to other regions. The connections list
other regions which this region will be joined to if some particular shuttle is
in one of a set of states. Connections are bidirectional - each connection from
A to B has a corresponding connection from B to A. (And the connection will
appear in both A.connections and B.connections).

Each region in the AST has the following properties:

- **engines**: List of engine IDs of engines which the region touches
- **connections**: Set of connections. The values are `{rid:otherRegionId, sid:shuttleId, inStates:[...]}`
- **pressure**: Total pressure of all connected engines. Mostly used for
debugging - we can't dedup engines with this.


### Engines

Each engine in the grid is listed in the AST. For simulation, engines have the
interesting property that they can only be counted once for each connected
space, regardless of how many faces of the engine are used. If two connected
regions both touch different faces of an engine, the pressure only changes by
1. However, if the regions aren't connected, they can both use the engine.

Each engine in the engine list contains `{x, y, pressure:-1 or 1, regions:[list
of region ids], exclusive:true if the engine only touches one region}`



## Utility methods

The compiler comes with a bunch of utility methods for printing ascii art grids
and updating grids based on shuttle states. There's going to be churn in these
methods - but they're exposed for convenience via
`require('boilerplate-compiler').util`.


