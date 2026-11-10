/* Fixed projection of validated JSON into the existing engine's interface. */
var PROTOTYPE_MAP = JSON.parse(document.getElementById('prototype-map').textContent);
var SCENARIO_STATE = JSON.parse(document.getElementById('scenario-state').textContent);
var SCENARIO_TITLES = Object.create(null);
var NAV_PATH = Object.create(null);
var STEPS = Object.create(null);
var STEPPER_LABELS = Object.create(null);
var PANEL_MAP = Object.create(null);
var AC_DATA = Object.create(null);
Object.keys(PROTOTYPE_MAP.routes).forEach(function(sid) {
  var route = PROTOTYPE_MAP.routes[sid];
  SCENARIO_TITLES[sid] = route.name;
  NAV_PATH[sid] = route.pages.slice();
  STEPS[sid] = route.pages.map(function(id, index) {
    return { id: id, label: PROTOTYPE_MAP.pages[id].label, dotIdx: index };
  });
  STEPPER_LABELS[sid] = STEPS[sid].map(function(step) { return step.label; });
  PANEL_MAP[sid] = 'scenario-' + sid;
  AC_DATA[sid] = Object.create(null);
  route.pages.forEach(function(id) { AC_DATA[sid][id] = PROTOTYPE_MAP.pages[id].acs; });
});

/* frames.js runs next and is arbitrary code. Deep-freeze the map and its projections and make
 * their global names read-only, so frame code cannot rewrite the data the AC panel and the
 * report are built from (it can still change the DOM and behavior). SCENARIO_STATE stays
 * mutable: frames keep form input there between steps. */
(function() {
  // Children first, so a frozen object always has a frozen subtree and shared arrays are walked once.
  function deepFreeze(value) {
    if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
      Object.keys(value).forEach(function(key) { deepFreeze(value[key]); });
      Object.freeze(value);
    }
    return value;
  }
  ['PROTOTYPE_MAP', 'SCENARIO_TITLES', 'NAV_PATH', 'STEPS', 'STEPPER_LABELS', 'PANEL_MAP', 'AC_DATA']
    .forEach(function(name) {
      // Pass the value too: in a Node vm context a descriptor without one leaves the binding undefined.
      Object.defineProperty(globalThis, name, {
        value: deepFreeze(globalThis[name]), enumerable: true, writable: false, configurable: false
      });
    });
})();
