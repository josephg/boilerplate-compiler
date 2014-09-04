// Generated from boilerplate-compiler v1 in fill mode 'engines'
// 1 shuttles, 12 regions and 8 engines
/* Compiled grid

;;;;;;;;
;;;-+;;;
;;    ;;
;+  S -;
;- SSS+;
;;  S ;;
;;;+-;;;
;;;;;;;;
            
 ; ; - + ; ; 
   2 0 1 3  
 ;2 2   3 3; 
   2     3  
 +4    S  5- 
            
 -6  S S S7+ 
   8     9  
 ;8 8  S9 9; 
   8 0 1 9  
 ; ; + - ; ; 
            

*/

(function(){
var shuttleState = new Uint8Array([3]);
var regionZone = new Uint32Array(12);
var base = 1;

var zonePressure = new Int8Array(12);
var successors = [0,2,0,1,1,3,0,1,0,2,2,3,1,3,2,3];

function calc1(z) {
  regionZone[1] = z;
  zonePressure[z - base] += 1;
  
  if (regionZone[3] !== z && shuttleState[0] === 0) calc3(z);
}
function calc2(z) {
  regionZone[2] = z;
  
  if (regionZone[4] !== z && shuttleState[0] >= 1 && shuttleState[0] < 3) calc4(z);
  if (regionZone[6] !== z && shuttleState[0] === 1) calc6(z);
  if (regionZone[8] !== z && shuttleState[0] === 1) calc8(z);
  if (regionZone[9] !== z && shuttleState[0] === 1) calc9(z);
  if (regionZone[10] !== z && shuttleState[0] === 1) calc10(z);
  if (regionZone[11] !== z && shuttleState[0] === 1) calc11(z);
}
function calc3(z) {
  regionZone[3] = z;
  
  if (regionZone[1] !== z && shuttleState[0] === 0) calc1(z);
  if (regionZone[5] !== z && shuttleState[0] === 0) calc5(z);
  if (regionZone[5] !== z && shuttleState[0] === 3) calc5(z);
  if (regionZone[7] !== z && shuttleState[0] === 0) calc7(z);
  if (regionZone[8] !== z && shuttleState[0] === 0) calc8(z);
  if (regionZone[9] !== z && shuttleState[0] === 0) calc9(z);
  if (regionZone[10] !== z && shuttleState[0] === 0) calc10(z);
  if (regionZone[11] !== z && shuttleState[0] === 0) calc11(z);
}
function calc4(z) {
  regionZone[4] = z;
  zonePressure[z - base] += 1;
  
  if (regionZone[2] !== z && shuttleState[0] >= 1 && shuttleState[0] < 3) calc2(z);
}
function calc5(z) {
  regionZone[5] = z;
  zonePressure[z - base] -= 1;
  
  if (regionZone[3] !== z && shuttleState[0] === 0) calc3(z);
  if (regionZone[3] !== z && shuttleState[0] === 3) calc3(z);
}
function calc6(z) {
  regionZone[6] = z;
  zonePressure[z - base] -= 1;
  
  if (regionZone[2] !== z && shuttleState[0] === 1) calc2(z);
  if (regionZone[8] !== z && shuttleState[0] === 0) calc8(z);
}
function calc7(z) {
  regionZone[7] = z;
  zonePressure[z - base] += 1;
  
  if (regionZone[3] !== z && shuttleState[0] === 0) calc3(z);
  if (regionZone[9] !== z && shuttleState[0] === 1) calc9(z);
}
function calc8(z) {
  regionZone[8] = z;
  
  if (regionZone[2] !== z && shuttleState[0] === 1) calc2(z);
  if (regionZone[3] !== z && shuttleState[0] === 0) calc3(z);
  if (regionZone[6] !== z && shuttleState[0] === 0) calc6(z);
  if (regionZone[10] !== z && shuttleState[0] === 3) calc10(z);
}
function calc9(z) {
  regionZone[9] = z;
  
  if (regionZone[2] !== z && shuttleState[0] === 1) calc2(z);
  if (regionZone[3] !== z && shuttleState[0] === 0) calc3(z);
  if (regionZone[7] !== z && shuttleState[0] === 1) calc7(z);
  if (regionZone[11] !== z && shuttleState[0] === 2) calc11(z);
}
function calc10(z) {
  regionZone[10] = z;
  zonePressure[z - base] += 1;
  
  if (regionZone[2] !== z && shuttleState[0] === 1) calc2(z);
  if (regionZone[3] !== z && shuttleState[0] === 0) calc3(z);
  if (regionZone[8] !== z && shuttleState[0] === 3) calc8(z);
}
function calc11(z) {
  regionZone[11] = z;
  zonePressure[z - base] -= 1;
  
  if (regionZone[2] !== z && shuttleState[0] === 1) calc2(z);
  if (regionZone[3] !== z && shuttleState[0] === 0) calc3(z);
  if (regionZone[9] !== z && shuttleState[0] === 2) calc9(z);
}

function step() {
  var nextZone = base;
  // Calculating zone for region 0
  var z;
  z = nextZone++;
  regionZone[0] = z;
  zonePressure[0] = -1;
  
  if (shuttleState[0] >= 2) calc1(z);
  if (shuttleState[0] >= 1) calc2(z);
  if (regionZone[3] !== z && shuttleState[0] >= 2) calc3(z);
  if (regionZone[4] !== z && shuttleState[0] === 3) calc4(z);
  if (regionZone[5] !== z && shuttleState[0] === 2) calc5(z);
  if (regionZone[6] !== z && shuttleState[0] === 3) calc6(z);
  if (regionZone[7] !== z && shuttleState[0] === 2) calc7(z);
  if (regionZone[8] !== z && shuttleState[0] === 3) calc8(z);
  if (regionZone[9] !== z && shuttleState[0] === 2) calc9(z);
  // Calculating zone for region 1
  if (regionZone[1] < base) {
    zonePressure[nextZone - base] = 0;
    calc1(nextZone++);
  }
  // Calculating zone for region 4
  if (regionZone[4] < base) {
    zonePressure[nextZone - base] = 0;
    calc4(nextZone++);
  }
  // Calculating zone for region 5
  if (regionZone[5] < base) {
    zonePressure[nextZone - base] = 0;
    calc5(nextZone++);
  }
  // Calculating zone for region 6
  if (regionZone[6] < base) {
    zonePressure[nextZone - base] = 0;
    calc6(nextZone++);
  }
  // Calculating zone for region 7
  if (regionZone[7] < base) {
    zonePressure[nextZone - base] = 0;
    calc7(nextZone++);
  }
  // Calculating zone for region 10
  if (regionZone[10] < base) {
    zonePressure[nextZone - base] = 0;
    calc10(nextZone++);
  }
  // Calculating zone for region 11
  if (regionZone[11] < base) {
    zonePressure[nextZone - base] = 0;
    calc11(nextZone++);
  }
  
  var force, state;
  var successor;
  // Y direction:
  
  // Calculating force for shuttle 0 (statemachine) with 4 states
  state = shuttleState[0];
  switch(state) {
    case 0:
      force =
        + (z = regionZone[0] - base, z < 0 ? 0 : zonePressure[z])
        + (z = regionZone[1] - base, z < 0 ? 0 : zonePressure[z])
        + (z = regionZone[2] - base, z < 0 ? 0 : zonePressure[z])
        + -2* (z = regionZone[3] - base, z < 0 ? 0 : zonePressure[z])
        - (z = regionZone[6] - base, z < 0 ? 0 : zonePressure[z])
      ;
      break;
    case 1:
      force =
        + (z = regionZone[0] - base, z < 0 ? 0 : zonePressure[z])
        + (z = regionZone[1] - base, z < 0 ? 0 : zonePressure[z])
        + -2* (z = regionZone[2] - base, z < 0 ? 0 : zonePressure[z])
        + (z = regionZone[3] - base, z < 0 ? 0 : zonePressure[z])
        - (z = regionZone[7] - base, z < 0 ? 0 : zonePressure[z])
      ;
      break;
    case 2:
      force =
        + 2* (z = regionZone[0] - base, z < 0 ? 0 : zonePressure[z])
        + (z = regionZone[2] - base, z < 0 ? 0 : zonePressure[z])
        - (z = regionZone[8] - base, z < 0 ? 0 : zonePressure[z])
        - (z = regionZone[9] - base, z < 0 ? 0 : zonePressure[z])
        - (z = regionZone[10] - base, z < 0 ? 0 : zonePressure[z])
      ;
      break;
    default:
      force =
        + 2* (z = regionZone[0] - base, z < 0 ? 0 : zonePressure[z])
        + (z = regionZone[3] - base, z < 0 ? 0 : zonePressure[z])
        - (z = regionZone[8] - base, z < 0 ? 0 : zonePressure[z])
        - (z = regionZone[9] - base, z < 0 ? 0 : zonePressure[z])
        - (z = regionZone[11] - base, z < 0 ? 0 : zonePressure[z])
      ;
  }
  successor = force === 0 ? state : successors[(force > 0 ? 1 : 0) + 4 * state];
  if (successor === state) {
    // X direction:
    
    // Calculating force for shuttle 0 (statemachine) with 4 states
    state = shuttleState[0];
    switch(state) {
      case 0:
        force =
          - (z = regionZone[1] - base, z < 0 ? 0 : zonePressure[z])
          + (z = regionZone[2] - base, z < 0 ? 0 : zonePressure[z])
          + -2* (z = regionZone[3] - base, z < 0 ? 0 : zonePressure[z])
          + (z = regionZone[4] - base, z < 0 ? 0 : zonePressure[z])
          + (z = regionZone[6] - base, z < 0 ? 0 : zonePressure[z])
        ;
        break;
      case 1:
        force =
          + (z = regionZone[0] - base, z < 0 ? 0 : zonePressure[z])
          + 2* (z = regionZone[2] - base, z < 0 ? 0 : zonePressure[z])
          - (z = regionZone[3] - base, z < 0 ? 0 : zonePressure[z])
          - (z = regionZone[5] - base, z < 0 ? 0 : zonePressure[z])
          - (z = regionZone[7] - base, z < 0 ? 0 : zonePressure[z])
        ;
        break;
      case 2:
        force =
          + -2* (z = regionZone[0] - base, z < 0 ? 0 : zonePressure[z])
          + (z = regionZone[2] - base, z < 0 ? 0 : zonePressure[z])
          + (z = regionZone[6] - base, z < 0 ? 0 : zonePressure[z])
          + (z = regionZone[8] - base, z < 0 ? 0 : zonePressure[z])
          - (z = regionZone[9] - base, z < 0 ? 0 : zonePressure[z])
        ;
        break;
      default:
        force =
          + 2* (z = regionZone[0] - base, z < 0 ? 0 : zonePressure[z])
          - (z = regionZone[3] - base, z < 0 ? 0 : zonePressure[z])
          - (z = regionZone[7] - base, z < 0 ? 0 : zonePressure[z])
          + (z = regionZone[8] - base, z < 0 ? 0 : zonePressure[z])
          - (z = regionZone[9] - base, z < 0 ? 0 : zonePressure[z])
        ;
    }
    successor = force === 0 ? state : successors[(force > 0 ? 3 : 2) + 4 * state];
  }
  shuttleState[0] = successor;
  base = nextZone;
}

module.exports = {states:shuttleState, step:step};
})();
