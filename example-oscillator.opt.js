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

var zonePressure = new Array(3);

function step() {
  var nextZone = base;

  zonePressure[nextZone - base] = 0;
  calc1(nextZone++);

  // Conditional not needed because its unreachable from already calculated values
  zonePressure[nextZone - base] = 0;
  calc2(nextZone++);

  var v = zonePressure[regionZone[1] - base] - zonePressure[regionZone[2] - base];
  if (v) {
    shuttleState[0] = v < 0 ? 1 : 0;
  }

  base = nextZone;
}

function calc0(v) {
  regionZone[0] = v;
  zonePressure[zone - base] += -1; // Engine exclusive.
  // calc1() call not needed because its already been called (via root).
  // calc2() call not needed because if this gets called before calc2 in the root, calc2 can't be in the zone.
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







