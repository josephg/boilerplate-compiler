/*

;;;;;;;;;
;;;;-;;;;
;;;; ;;;;
;;;  ;;;;
;x SsSSx;
; ;b ;; ;
;  b ;; ;
;;;b;;; ;
;;;     ;
;;;;;;;;;
              
 ; ; ; - ; ; ; 
       0      
 ; ; ;0 0; ; ; 
     0 0      
 ; ;0 0 0; ; ; 
 1   0 0     2
1x1  S s S S2x2
 1   2 1     2
1 1;1b1 1; ;2 2
 1 1 2 1     2
1 1 1b1 1; ;2 2
 1 1 2 1     2
 ; ;3b3; ; ;2 2
     2 2 2 2 2
 ; ;2 2 2 2 2 2
     2 2 2 2 2

*/

var shuttleState = [0];

var regionZone = [0,0,0];

var base = 1;

// Theoretical maximum number of zones = number of regions. (Or max(#regions,
// #engines)). Actually, there could be far fewer if there's zone mutual
// exclusion nonsense.
var zonePressure = new Array(3);

// This is only needed because engine sides can be reused in different zones by
// the same region. Kinda ugh.
var engineLastUsedBy = new Array(1); // #engines

function addEngine(zone, engine, engineValue) {
  if (engineLastUsedBy[engine] != zone) {
    zonePressure[zone - base] += engineValue;
    engineLastUsedBy[engine] = zone;
  }
}

// What regions do we need to calculate?
//
// Options:
// - Everywhere with an engine (feed forward). Might be better for situations
//   where we need the pressure of every region.
// - Every zone with a shuttle movement dependancy (feed back). Most efficient.

function step() {
  var nextZone = base;

  // Only these two regions control the shuttle.
  if (regionZone[1] < base) {
    zonePressure[nextZone - base] = 0;
    calc1(nextZone++);
  }
  if (regionZone[2] < base) {
    zonePressure[nextZone - base] = 0;
    calc2(nextZone++);
  }

  // Then move shuttles based on the pressure. Calculate force rightward
  var v = zonePressure[regionZone[1] - base] - zonePressure[regionZone[2] - base];
  if (v) {
    // if (shuttleState[0] == 0) { .... } else ... 
    // This needs to be more complicated for shuttles which go in x & y directions
    shuttleState[0] = v < 0 ? 1 : 0;
  }

  base = nextZone;
}


function calc0(v) {
  regionZone[0] = v;
  addEngine(v, 0, -1);

  if (regionZone[1] !== v && shuttleState[0] === 0) calc1(v);
  if (regionZone[2] !== v && shuttleState[0] === 1) calc2(v);
}

function calc1(v) {
  regionZone[1] = v;
  if (regionZone[0] !== v && shuttleState[0] === 0) calc0(v);
}

function calc2(v) {
  regionZone[2] = v;
  if (regionZone[0] !== v && shuttleState[0] === 1) calc0(v);
}


/*
console.log('pressure', zonePressure);
console.log('num zones', nextZone - base);
console.log('region zones', regionZone);
*/

for (var i = 0; i < 10; i++) {
  step();
  console.log(shuttleState);
}







