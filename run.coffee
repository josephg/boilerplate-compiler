# Simple script to run the compiled output and print out the states each step

script = process.argv[2]

{states, step} = require "./#{script}"
console.log "running #{script}"

step() for [1..11]

for [1..20]
  console.log 'states: ', (states[i] for i in [0...states.length])
  step()

