/*

;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;S;;;;;;;;;;;;;
;-          s    ;;;;;;;;;
;;;;; ;;;;;;S;;; ;;;;;;;;;
;;;;; ;;;;;; ;;; ;;;;;;;;;
;;;;; ;;;;;;;;;; ;;;;;;;;;
;;;;Ss;;;;;;;;;; ;;;;;;;;;
;;;;; ;;;;;;;;;; ;;;;;;;;;
;;;;; ;;;;;; ;;; ;;S;;;;;;
;;;;;       S      s  xS ;
;;;;;;;;;;;;s;;;;;;S;;;;;;
;;;;;;;;;;;;S;;;;;; ;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;
                                                
 ; ; ; ; ; ; ; ; ; ; ; S ; ; ; ; ; ; ; ; ; ; ; ; 
   0 0 0 0 0 0 0 0 0 0   1 1 1 1                
 -0 0 0 0 0 0 0 0 0 0 0s1 1 1 1 1; ; ; ; ; ; ; ; 
   0 0 0 0 0 0 0 0 0 0   1 1 1 1                
 ; ; ; ;0 0; ; ; ; ; ; S ; ; ;1 1; ; ; ; ; ; ; ; 
         0                     1                
 ; ; ; ;0 0; ; ; ; ; ;   ; ; ;1 1; ; ; ; ; ; ; ; 
         0                     1                
 ; ; ; ;0 0; ; ; ; ; ; ; ; ; ;1 1; ; ; ; ; ; ; ; 
         0                     1                
 ; ; ; S s ; ; ; ; ; ; ; ; ; ;1 1; ; ; ; ; ; ; ; 
         2                     1                
 ; ; ; ;2 2; ; ; ; ; ; ; ; ; ;1 1; ; ; ; ; ; ; ; 
         2                     1                
 ; ; ; ;2 2; ; ; ; ; ;   ; ; ;1 1; ; S ; ; ; ; ; 
         2 2 2 2 2 2 2   1 1 1 1 1 1   3 3 3    
 ; ; ; ;2 2 2 2 2 2 2 2S1 1 1 1 1 1 1s3 3 3x3S   
         2 2 2 2 2 2 2   1 1 1 1 1 1   3 3 3    
 ; ; ; ; ; ; ; ; ; ; ; s ; ; ; ; ; ; S ; ; ; ; ; 
                                                
 ; ; ; ; ; ; ; ; ; ; ; S ; ; ; ; ; ;   ; ; ; ; ; 

*/

var shuttleState = [0,0,0,0];

var regionZone = [0,0,0,0];

var base = 1;

// Theoretical maximum number of zones = number of regions. (Or max(#regions, #engines))
var zonePressure = new Array(4);

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

var nextZone = base;
if (regionZone[3] < base) {
  zonePressure[nextZone - base] = 0;
  calc3(nextZone++);
}
// And more based on what we need to calculate.
if (regionZone[1] < base) {
  zonePressure[nextZone - base] = 0;
  calc1(nextZone++);
}
if (regionZone[2] < base) {
  zonePressure[nextZone - base] = 0;
  calc2(nextZone++);
}
if (regionZone[0] < base) {
  zonePressure[nextZone - base] = 0;
  calc0(nextZone++);
}


function calc3(v) {
  regionZone[3] = v;
  if (regionZone[1] !== v && shuttleState[3] === 0) calc1(v);
}

function calc1(v) {
  regionZone[1] = v;
  if (regionZone[3] !== v && shuttleState[3] === 0) calc3(v);
  if (regionZone[0] !== v && shuttleState[0] === 0) calc0(v);
  if (regionZone[2] !== v && shuttleState[2] === 1) calc2(v);
}

function calc0(v) {
  regionZone[0] = v;
  addEngine(v, 0, -1);
  if (regionZone[1] !== v && shuttleState[0] === 0) calc1(v);
  if (regionZone[2] !== v && shuttleState[1] === 0) calc2(v);
}

function calc2(v) {
  regionZone[2] = v;
  if (regionZone[0] !== v && shuttleState[1] === 0) calc0(v);
  if (regionZone[1] !== v && shuttleState[2] === 1) calc1(v);
}


console.log('pressure', zonePressure);
console.log('num zones', nextZone - base);
console.log('region zones', regionZone);








