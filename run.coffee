script = process.argv[2]

{states, step} = require "./#{script}"
console.log "running #{script}"

for [1..20]
  console.log 'states: ', (states[i] for i in [0...states.length])
  step()

