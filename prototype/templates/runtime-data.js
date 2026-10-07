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
