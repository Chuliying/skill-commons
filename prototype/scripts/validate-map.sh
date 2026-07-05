#!/usr/bin/env bash
# ================================================================
# validate-map.sh — PrototypeMap JSON 驗證腳本
# ================================================================
# 用途：G4 Freeze 時驗證 prototype-map-v{N}.json 的結構完整性
# 使用：bash validate-map.sh <path-to-map.json>
# 回傳：0 = 通過, 1 = 失敗
# ================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

fail() { echo -e "${RED}✗ $1${NC}"; ERRORS=$((ERRORS + 1)); }
pass() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; WARNINGS=$((WARNINGS + 1)); }

# --- Args ---
if [ $# -lt 1 ]; then
  echo "Usage: bash validate-map.sh <path-to-map.json>"
  exit 1
fi

MAP_FILE="$1"

if [ ! -f "$MAP_FILE" ]; then
  fail "File not found: $MAP_FILE"
  exit 1
fi

# --- Check jq available ---
if ! command -v jq &>/dev/null; then
  echo -e "${RED}Error: jq is required. Install: brew install jq${NC}"
  exit 1
fi

# --- Validate JSON syntax ---
if ! jq empty "$MAP_FILE" 2>/dev/null; then
  fail "Invalid JSON syntax"
  exit 1
fi
pass "Valid JSON syntax"

echo ""
echo "=== 1. Meta Validation ==="

# meta.projectName
if jq -e '.meta.projectName' "$MAP_FILE" >/dev/null 2>&1; then
  pass "meta.projectName exists: $(jq -r '.meta.projectName' "$MAP_FILE")"
else
  fail "meta.projectName missing"
fi

# meta.prdVersion
if jq -e '.meta.prdVersion' "$MAP_FILE" >/dev/null 2>&1; then
  pass "meta.prdVersion exists: $(jq -r '.meta.prdVersion' "$MAP_FILE")"
else
  fail "meta.prdVersion missing"
fi

# meta.shellType
SHELL_TYPE=$(jq -r '.meta.shellType // empty' "$MAP_FILE")
if [ -n "$SHELL_TYPE" ]; then
  if [ "$SHELL_TYPE" = "flow" ] || [ "$SHELL_TYPE" = "standard" ]; then
    pass "meta.shellType valid: $SHELL_TYPE"
  else
    fail "meta.shellType invalid: $SHELL_TYPE (must be 'flow' or 'standard')"
  fi
else
  fail "meta.shellType missing"
fi

# meta.frozenAt
if jq -e '.meta.frozenAt' "$MAP_FILE" >/dev/null 2>&1; then
  pass "meta.frozenAt exists: $(jq -r '.meta.frozenAt' "$MAP_FILE")"
else
  fail "meta.frozenAt missing (map not frozen?)"
fi

# meta.createdAt
if jq -e '.meta.createdAt' "$MAP_FILE" >/dev/null 2>&1; then
  pass "meta.createdAt exists"
else
  warn "meta.createdAt missing"
fi

echo ""
echo "=== 2. Routes Validation ==="

ROUTE_COUNT=$(jq '.routes | length' "$MAP_FILE")
if [ "$ROUTE_COUNT" -gt 0 ]; then
  pass "routes count: $ROUTE_COUNT"
else
  fail "routes is empty"
fi

# Each route must have name and pages[]
for key in $(jq -r '.routes | keys[]' "$MAP_FILE"); do
  NAME=$(jq -r ".routes[\"$key\"].name // empty" "$MAP_FILE")
  PAGES_COUNT=$(jq ".routes[\"$key\"].pages | length" "$MAP_FILE")
  if [ -z "$NAME" ]; then
    fail "routes.$key.name missing"
  fi
  if [ "$PAGES_COUNT" -eq 0 ]; then
    fail "routes.$key.pages is empty"
  else
    pass "routes.$key: name='$NAME', pages=$PAGES_COUNT"
  fi
done

echo ""
echo "=== 3. Pages Validation ==="

PAGE_COUNT=$(jq '.pages | length' "$MAP_FILE")
if [ "$PAGE_COUNT" -gt 0 ]; then
  pass "pages count: $PAGE_COUNT"
else
  fail "pages is empty"
fi

TOTAL_ACS=0
PAGES_NO_AC=0

for key in $(jq -r '.pages | keys[]' "$MAP_FILE"); do
  LABEL=$(jq -r ".pages[\"$key\"].label // empty" "$MAP_FILE")
  FRAME_REF=$(jq -r ".pages[\"$key\"].frameRef // empty" "$MAP_FILE")
  AC_COUNT=$(jq ".pages[\"$key\"].acs | length" "$MAP_FILE" 2>/dev/null || echo "0")
  TOTAL_ACS=$((TOTAL_ACS + AC_COUNT))

  if [ -z "$LABEL" ]; then
    fail "pages.$key.label missing"
  fi

  if [ "$AC_COUNT" -eq 0 ]; then
    PAGES_NO_AC=$((PAGES_NO_AC + 1))
    warn "pages.$key has 0 ACs"
  fi
done

pass "Total ACs: $TOTAL_ACS"
if [ "$PAGES_NO_AC" -gt 0 ]; then
  warn "$PAGES_NO_AC page(s) have no ACs"
fi

echo ""
echo "=== 4. Foreign Key Check (routes.pages → pages keys) ==="

MISSING_FK=0
for route_key in $(jq -r '.routes | keys[]' "$MAP_FILE"); do
  for page_ref in $(jq -r ".routes[\"$route_key\"].pages[]" "$MAP_FILE"); do
    if ! jq -e ".pages[\"$page_ref\"]" "$MAP_FILE" >/dev/null 2>&1; then
      fail "routes.$route_key references page '$page_ref' but pages.$page_ref not found"
      MISSING_FK=$((MISSING_FK + 1))
    fi
  done
done

if [ "$MISSING_FK" -eq 0 ]; then
  pass "All route page references resolved"
fi

echo ""
echo "=== 5. AC prd Field — No Abbreviation Check ==="

ABBREV_COUNT=0
# Check for common abbreviation patterns in prd fields
ABBREV_MATCHES=$(jq -r '[.pages[].acs[]? | select(.prd != null) | .prd] | map(select(test("同 [0-9S]|同上|見 [0-9S]|參見|同 S[0-9]"; "i"))) | length' "$MAP_FILE" 2>/dev/null || echo "0")
if [ "$ABBREV_MATCHES" -gt 0 ]; then
  fail "Found $ABBREV_MATCHES AC(s) with abbreviated prd references (禁止「同 X-X-X」等縮寫)"
else
  pass "No abbreviated prd references found"
fi

echo ""
echo "=== 6. Coverage Info ==="

COVERAGE=$(jq -r '.meta.coverageRate // empty' "$MAP_FILE")
if [ -n "$COVERAGE" ]; then
  pass "Coverage rate: ${COVERAGE}%"
  GAPS_COUNT=$(jq '.meta.gaps | length' "$MAP_FILE" 2>/dev/null || echo "0")
  if [ "$GAPS_COUNT" -gt 0 ]; then
    warn "$GAPS_COUNT gap(s) acknowledged"
  fi
else
  warn "meta.coverageRate not set (will be set in G4)"
fi

# --- Schema Version Detection ---
SCHEMA_VER=$(jq -r '.meta.schemaVersion // empty' "$MAP_FILE")
if [ -z "$SCHEMA_VER" ]; then
  SCHEMA_VER=1
  warn "meta.schemaVersion missing — treating as v1 (legacy), skipping v4 rules"
else
  pass "meta.schemaVersion: $SCHEMA_VER"
fi

# --- v4 Rules (schemaVersion >= 2 only) ---
if [ "$SCHEMA_VER" -ge 2 ]; then

  echo ""
  echo "=== 7. flow-step / flowId Check (v4) ==="

  FLOW_ERRORS=0
  for key in $(jq -r '.pages | keys[]' "$MAP_FILE"); do
    PAGE_TYPE=$(jq -r ".pages[\"$key\"].type // \"surface\"" "$MAP_FILE")
    FLOW_ID=$(jq -r ".pages[\"$key\"].flowId // empty" "$MAP_FILE")
    if [ "$PAGE_TYPE" = "flow-step" ] && [ -z "$FLOW_ID" ]; then
      fail "pages.$key: type=flow-step but flowId missing"
      FLOW_ERRORS=$((FLOW_ERRORS + 1))
    fi
    if [ "$PAGE_TYPE" = "surface" ] && [ -n "$FLOW_ID" ]; then
      warn "pages.$key: type=surface but has flowId='$FLOW_ID' (unexpected)"
    fi
  done
  if [ "$FLOW_ERRORS" -eq 0 ]; then
    pass "All flow-step pages have flowId"
  fi

  # Same flowId pages must be in same route
  for fid in $(jq -r '[.pages[] | select(.flowId != null) | .flowId] | unique[]' "$MAP_FILE" 2>/dev/null); do
    FLOW_PAGES=$(jq -r "[.pages | to_entries[] | select(.value.flowId == \"$fid\") | .key][]" "$MAP_FILE")
    ROUTES_FOR_FLOW=$(for fp in $FLOW_PAGES; do
      jq -r ".routes | to_entries[] | select(.value.pages | index(\"$fp\")) | .key" "$MAP_FILE"
    done | sort -u)
    if [ -z "$ROUTES_FOR_FLOW" ]; then
      fail "flowId '$fid' pages not referenced by any route"
    else
      ROUTE_COUNT_FOR_FLOW=$(echo "$ROUTES_FOR_FLOW" | wc -l | tr -d ' ')
      if [ "$ROUTE_COUNT_FOR_FLOW" -gt 1 ]; then
        fail "flowId '$fid' spans multiple routes: $(echo $ROUTES_FOR_FLOW | tr '\n' ', ')"
      else
        pass "flowId '$fid' contained in single route"
      fi
    fi
  done

  # Reverse FK: every flow-step page must be referenced by at least one route
  for key in $(jq -r '.pages | to_entries[] | select(.value.type == "flow-step") | .key' "$MAP_FILE"); do
    FOUND=$(jq -r ".routes[] | select(.pages | index(\"$key\")) | .pages[0]" "$MAP_FILE" 2>/dev/null)
    if [ -z "$FOUND" ]; then
      fail "pages.$key (flow-step) not referenced by any route"
    fi
  done

  echo ""
  echo "=== 8. frameRef Foreign Key Check (v4) ==="

  HAS_FRAMES=$(jq -e '.frames // empty' "$MAP_FILE" >/dev/null 2>&1 && echo "yes" || echo "no")
  if [ "$HAS_FRAMES" = "yes" ]; then
    FRAME_FK_ERRORS=0
    for key in $(jq -r '.pages | keys[]' "$MAP_FILE"); do
      FREF=$(jq -r ".pages[\"$key\"].frameRef // empty" "$MAP_FILE")
      if [ -n "$FREF" ]; then
        if ! jq -e ".frames[\"$FREF\"]" "$MAP_FILE" >/dev/null 2>&1; then
          fail "pages.$key.frameRef='$FREF' not found in frames{}"
          FRAME_FK_ERRORS=$((FRAME_FK_ERRORS + 1))
        fi
      fi
    done
    if [ "$FRAME_FK_ERRORS" -eq 0 ]; then
      pass "All frameRef values resolve to frames{}"
    fi

    echo ""
    echo "=== 9. frames{} Schema Validation (v4) ==="

    for fkey in $(jq -r '.frames | keys[]' "$MAP_FILE"); do
      SHELL_VAL=$(jq -r ".frames[\"$fkey\"].shell // empty" "$MAP_FILE")
      if [ -z "$SHELL_VAL" ]; then
        fail "frames.$fkey.shell missing"
      fi
      SEC_COUNT=$(jq ".frames[\"$fkey\"].sections | length" "$MAP_FILE" 2>/dev/null || echo "0")
      if [ "$SEC_COUNT" -eq 0 ]; then
        fail "frames.$fkey.sections is empty"
      else
        # Check row uniqueness
        UNIQUE_ROWS=$(jq "[.frames[\"$fkey\"].sections[].row] | unique | length" "$MAP_FILE")
        if [ "$UNIQUE_ROWS" -ne "$SEC_COUNT" ]; then
          fail "frames.$fkey: sections.row values not unique ($UNIQUE_ROWS unique vs $SEC_COUNT total)"
        else
          pass "frames.$fkey: $SEC_COUNT sections, rows unique"
        fi
        # Check span range, count integer, and label required
        for idx in $(seq 0 $((SEC_COUNT - 1))); do
          LABEL_VAL=$(jq -r ".frames[\"$fkey\"].sections[$idx].label // empty" "$MAP_FILE")
          if [ -z "$LABEL_VAL" ]; then
            fail "frames.$fkey.sections[$idx].label missing (required)"
          fi
          SPAN=$(jq ".frames[\"$fkey\"].sections[$idx].span" "$MAP_FILE")
          if [ "$SPAN" -lt 1 ] || [ "$SPAN" -gt 12 ] 2>/dev/null; then
            fail "frames.$fkey.sections[$idx].span=$SPAN out of range (1-12)"
          fi
          CNT=$(jq ".frames[\"$fkey\"].sections[$idx].count // empty" "$MAP_FILE")
          if [ -n "$CNT" ] && [ "$CNT" != "null" ]; then
            if ! [[ "$CNT" =~ ^[1-9][0-9]*$ ]]; then
              fail "frames.$fkey.sections[$idx].count=$CNT not a positive integer"
            fi
          fi
        done
      fi
    done
  else
    warn "frames{} not present — skipping frameRef FK and frames schema checks"
  fi

  echo ""
  echo "=== 10. Key Format Check (v4) ==="

  KEY_FORMAT_ERR=0
  for key in $(jq -r '.routes | keys[]' "$MAP_FILE"); do
    if ! [[ "$key" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      fail "routes key '$key' contains unsafe characters"
      KEY_FORMAT_ERR=$((KEY_FORMAT_ERR + 1))
    fi
  done
  for key in $(jq -r '.pages | keys[]' "$MAP_FILE"); do
    if ! [[ "$key" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      fail "pages key '$key' contains unsafe characters"
      KEY_FORMAT_ERR=$((KEY_FORMAT_ERR + 1))
    fi
  done
  if [ "$KEY_FORMAT_ERR" -eq 0 ]; then
    pass "All route/page keys use safe format [a-zA-Z0-9_-]"
  fi

fi

# --- Summary ---
echo ""
echo "==============================="
echo "  Validation Summary"
echo "==============================="
echo "  Routes: $ROUTE_COUNT"
echo "  Pages:  $PAGE_COUNT"
echo "  ACs:    $TOTAL_ACS"
echo "  Errors: $ERRORS"
echo "  Warnings: $WARNINGS"
echo "==============================="

if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}FAILED — $ERRORS error(s) found${NC}"
  exit 1
else
  echo -e "${GREEN}PASSED${NC}"
  exit 0
fi
