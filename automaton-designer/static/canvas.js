// ---------------------------------------------------------------------------
// canvas.js — Automaton visualisation on HTML5 Canvas
// ---------------------------------------------------------------------------
// Receives automaton data from Haskell (via threepenny FFI) and renders
// states as circles and transitions as arrows.  Supports drag-to-move for
// states and highlights active states during simulation.
// ---------------------------------------------------------------------------

var canvasState = {
  states:       [],   // [{name, x, y, isStart, isAccept}]
  transitions:  [],   // [{from, to, label}]
  activeStates: [],   // names of currently highlighted states
  selectedState: null,
  dragging:      null,
  dragOffset:    {x: 0, y: 0}
};

var STATE_RADIUS = 30;

var C = {
  bg:              '#11111b',
  stateFill:       '#313244',
  stateStroke:     '#cdd6f4',
  stateText:       '#cdd6f4',
  activeFill:      '#2d4a2e',
  activeStroke:    '#a6e3a1',
  acceptRing:      '#f9e2af',
  startArrow:      '#89b4fa',
  selectedStroke:  '#89b4fa',
  transition:      '#9399b2',
  transText:       '#bac2de'
};

// ── Initialise canvas and attach mouse listeners ──────────────────────────

function initCanvas(canvasId) {
  var canvas = document.getElementById(canvasId);
  if (!canvas) return;

  // Resize canvas to container
  function resize() {
    var parent = canvas.parentElement;
    if (parent) {
      canvas.width  = parent.clientWidth;
      canvas.height = parent.clientHeight;
      drawAutomaton(canvasId);
    }
  }
  window.addEventListener('resize', resize);
  setTimeout(resize, 50);

  // ── Mouse: drag states ──────────────────────────────────────────────
  canvas.addEventListener('mousedown', function(e) {
    var rect = canvas.getBoundingClientRect();
    var mx = e.clientX - rect.left;
    var my = e.clientY - rect.top;
    for (var i = 0; i < canvasState.states.length; i++) {
      var s = canvasState.states[i];
      var dx = mx - s.x, dy = my - s.y;
      if (dx*dx + dy*dy <= STATE_RADIUS * STATE_RADIUS) {
        canvasState.dragging = i;
        canvasState.dragOffset = {x: dx, y: dy};
        canvasState.selectedState = s.name;
        break;
      }
    }
    drawAutomaton(canvasId);
  });

  canvas.addEventListener('mousemove', function(e) {
    if (canvasState.dragging !== null) {
      var rect = canvas.getBoundingClientRect();
      canvasState.states[canvasState.dragging].x = e.clientX - rect.left - canvasState.dragOffset.x;
      canvasState.states[canvasState.dragging].y = e.clientY - rect.top  - canvasState.dragOffset.y;
      drawAutomaton(canvasId);
    }
  });

  canvas.addEventListener('mouseup', function() {
    canvasState.dragging = null;
  });
}

// ── Data setters called from Haskell ──────────────────────────────────────

function setAutomatonData(jsonStr) {
  try {
    var data = (typeof jsonStr === 'string') ? JSON.parse(jsonStr) : jsonStr;
    canvasState.states      = data.states      || [];
    canvasState.transitions = data.transitions || [];
    canvasState.activeStates = data.activeStates || [];
  } catch(e) { console.error('setAutomatonData parse error', e); }
}

function setActiveStates(names) {
  canvasState.activeStates = names || [];
}

function clearActiveStates() {
  canvasState.activeStates = [];
}

// ── Main draw routine ─────────────────────────────────────────────────────

function drawAutomaton(canvasId) {
  var canvas = document.getElementById(canvasId);
  if (!canvas) return;
  var ctx = canvas.getContext('2d');
  var w = canvas.width, h = canvas.height;

  // Background
  ctx.fillStyle = C.bg;
  ctx.fillRect(0, 0, w, h);

  // Draw grid dots (subtle)
  ctx.fillStyle = '#1e1e2e';
  for (var gx = 20; gx < w; gx += 40)
    for (var gy = 20; gy < h; gy += 40)
      ctx.fillRect(gx, gy, 1, 1);

  // Transitions first (below states)
  canvasState.transitions.forEach(function(t) { drawTransition(ctx, t); });

  // States on top
  canvasState.states.forEach(function(s) { drawState(ctx, s); });

  // Legend when empty
  if (canvasState.states.length === 0) {
    ctx.fillStyle = '#45475a';
    ctx.font = '14px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('Define an automaton in the DSL editor →', w/2, h/2);
  }
}

// ── Draw a single state ───────────────────────────────────────────────────

function drawState(ctx, s) {
  var isActive   = canvasState.activeStates.indexOf(s.name) >= 0;
  var isSelected = canvasState.selectedState === s.name;

  // Outer circle
  ctx.beginPath();
  ctx.arc(s.x, s.y, STATE_RADIUS, 0, 2*Math.PI);
  ctx.fillStyle   = isActive ? C.activeFill : C.stateFill;
  ctx.fill();
  ctx.lineWidth   = isSelected ? 3 : 2;
  ctx.strokeStyle = isActive ? C.activeStroke
                  : isSelected ? C.selectedStroke
                  : C.stateStroke;
  ctx.stroke();

  // Inner ring for accept states
  if (s.isAccept) {
    ctx.beginPath();
    ctx.arc(s.x, s.y, STATE_RADIUS - 5, 0, 2*Math.PI);
    ctx.strokeStyle = isActive ? C.activeStroke : C.acceptRing;
    ctx.lineWidth = 2;
    ctx.stroke();
  }

  // Start-state arrow
  if (s.isStart) {
    var ax = s.x - STATE_RADIUS;
    ctx.beginPath();
    ctx.moveTo(ax - 28, s.y);
    ctx.lineTo(ax - 3,  s.y);
    ctx.strokeStyle = C.startArrow;
    ctx.lineWidth = 2;
    ctx.stroke();
    // arrowhead
    ctx.beginPath();
    ctx.moveTo(ax - 3,  s.y);
    ctx.lineTo(ax - 11, s.y - 5);
    ctx.lineTo(ax - 11, s.y + 5);
    ctx.closePath();
    ctx.fillStyle = C.startArrow;
    ctx.fill();
  }

  // State label
  ctx.fillStyle  = isActive ? C.activeStroke : C.stateText;
  ctx.font       = '14px monospace';
  ctx.textAlign  = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(s.name, s.x, s.y);
}

// ── Draw a transition arrow ───────────────────────────────────────────────

function drawTransition(ctx, t) {
  var from = findState(t.from);
  var to   = findState(t.to);
  if (!from || !to) return;

  if (t.from === t.to) { drawSelfLoop(ctx, from, t.label); return; }

  // Check for bidirectional transitions → add curvature
  var hasPair = canvasState.transitions.some(function(o) {
    return o.from === t.to && o.to === t.from;
  });

  var dx = to.x - from.x, dy = to.y - from.y;
  var dist = Math.sqrt(dx*dx + dy*dy);
  if (dist === 0) return;
  var nx = dx/dist, ny = dy/dist;        // unit direction
  var px = -ny,     py = nx;              // perpendicular

  var curve = hasPair ? 22 : 0;

  var sx = from.x + nx*STATE_RADIUS + px*curve*0.4;
  var sy = from.y + ny*STATE_RADIUS + py*curve*0.4;
  var ex = to.x   - nx*STATE_RADIUS + px*curve*0.4;
  var ey = to.y   - ny*STATE_RADIUS + py*curve*0.4;
  var mx = (sx+ex)/2 + px*curve;
  var my = (sy+ey)/2 + py*curve;

  ctx.beginPath();
  ctx.moveTo(sx, sy);
  if (hasPair) ctx.quadraticCurveTo(mx, my, ex, ey);
  else         ctx.lineTo(ex, ey);
  ctx.strokeStyle = C.transition;
  ctx.lineWidth = 1.5;
  ctx.stroke();

  // Arrowhead
  var angle = hasPair ? Math.atan2(ey-my, ex-mx) : Math.atan2(dy, dx);
  var al = 10;
  ctx.beginPath();
  ctx.moveTo(ex, ey);
  ctx.lineTo(ex - al*Math.cos(angle-0.3), ey - al*Math.sin(angle-0.3));
  ctx.lineTo(ex - al*Math.cos(angle+0.3), ey - al*Math.sin(angle+0.3));
  ctx.closePath();
  ctx.fillStyle = C.transition;
  ctx.fill();

  // Label
  var lx, ly;
  if (hasPair) { lx = mx + px*12; ly = my + py*12; }
  else         { lx = (sx+ex)/2 + px*14; ly = (sy+ey)/2 + py*14; }
  ctx.fillStyle = C.transText;
  ctx.font = '13px monospace';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(t.label, lx, ly);
}

// ── Self-loop ─────────────────────────────────────────────────────────────

function drawSelfLoop(ctx, s, label) {
  var cx = s.x, cy = s.y - STATE_RADIUS - 16;
  var lr = 16;

  ctx.beginPath();
  ctx.arc(cx, cy, lr, 0.3*Math.PI, 0.7*Math.PI, true);
  ctx.strokeStyle = C.transition;
  ctx.lineWidth = 1.5;
  ctx.stroke();

  // small arrowhead
  var ae = 0.3 * Math.PI;
  var ax = cx + lr*Math.cos(ae), ay = cy + lr*Math.sin(ae);
  ctx.beginPath();
  ctx.moveTo(ax, ay);
  ctx.lineTo(ax+2, ay-9);
  ctx.lineTo(ax+8, ay-1);
  ctx.closePath();
  ctx.fillStyle = C.transition;
  ctx.fill();

  // label
  ctx.fillStyle = C.transText;
  ctx.font = '13px monospace';
  ctx.textAlign = 'center';
  ctx.fillText(label, cx, cy - lr - 6);
}

// ── Helper ────────────────────────────────────────────────────────────────

function findState(name) {
  for (var i = 0; i < canvasState.states.length; i++)
    if (canvasState.states[i].name === name) return canvasState.states[i];
  return null;
}
