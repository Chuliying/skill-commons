#!/usr/bin/env bash
# ================================================================
# scan-sitemap.sh — 機械式路由掃描，產出 sitemap JSON
# ================================================================
# 用途：掃描 React / Next.js 專案的路由結構與 menu 定義
# 使用：bash scan-sitemap.sh [project-root]
# 輸出：JSON 到 stdout（由 AI 接收後寫入 sitemap.json）
# 注意：本腳本只讀取不修改任何檔案
# 相容：macOS (BSD) + Linux (GNU)
# ================================================================

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT"

# --- Check dependencies ---
if ! command -v jq &>/dev/null; then
  echo '{"error": "jq is required. Install: brew install jq"}' >&2
  exit 1
fi
if ! command -v node &>/dev/null; then
  echo '{"error": "node is required for tree extraction."}' >&2
  exit 1
fi

TODAY=$(date +%Y-%m-%d)

# ================================================================
# S1: 偵測框架
# ================================================================
FRAMEWORK=""
ENTRY_DIR=""

if [ -d "src/app" ] && find src/app \( -name "page.tsx" -o -name "page.jsx" \) -print -quit 2>/dev/null | grep -q .; then
  FRAMEWORK="nextjs-app-router"
  ENTRY_DIR="src/app/"
elif [ -d "app" ] && find app \( -name "page.tsx" -o -name "page.jsx" \) -print -quit 2>/dev/null | grep -q .; then
  FRAMEWORK="nextjs-app-router"
  ENTRY_DIR="app/"
elif [ -d "src/pages" ] && find src/pages \( -name "*.tsx" -o -name "*.jsx" \) -not -name "_*" -print -quit 2>/dev/null | grep -q .; then
  FRAMEWORK="nextjs-pages-router"
  ENTRY_DIR="src/pages/"
elif [ -d "pages" ] && find pages \( -name "*.tsx" -o -name "*.jsx" \) -not -name "_*" -print -quit 2>/dev/null | grep -q .; then
  FRAMEWORK="nextjs-pages-router"
  ENTRY_DIR="pages/"
elif [ -f "package.json" ] && grep -q "react-router" package.json 2>/dev/null; then
  FRAMEWORK="react-router"
  ENTRY_DIR="src/"
else
  echo '{"error": "Cannot detect framework. No app/, pages/, or react-router found."}' >&2
  exit 1
fi

# ================================================================
# S2: 掃描路由結構
# ================================================================
ROUTES_JSON="[]"

if [ "$FRAMEWORK" = "nextjs-app-router" ]; then
  while IFS= read -r page_file; do
    # Remove entry dir prefix and /page.tsx suffix
    route_path="${page_file#"$ENTRY_DIR"}"
    route_path="${route_path%/page.tsx}"
    route_path="${route_path%/page.jsx}"

    # Root page.tsx → empty (will become /)
    if [ "$route_path" = "page.tsx" ] || [ "$route_path" = "page.jsx" ] || [ -z "$route_path" ]; then
      route_path=""
    fi

    # Skip api routes
    if [[ "$route_path" == api/* ]]; then
      continue
    fi

    # Detect dynamic segments
    IS_DYNAMIC=false
    DYNAMIC_TYPE="none"
    if [[ "$route_path" == *"[..."*"]"* ]]; then
      IS_DYNAMIC=true
      DYNAMIC_TYPE="catch-all"
    elif [[ "$route_path" == *"["*"]"* ]]; then
      IS_DYNAMIC=true
      DYNAMIC_TYPE="param"
    fi

    # Strip route groups — (groupName) directories don't produce URL segments
    CLEAN_PATH=$(echo "$route_path" | sed 's|([^)]*)/?||g' | sed 's|//|/|g' | sed 's|^/||' | sed 's|/$||')

    # Check for layout.tsx in same or parent directory
    HAS_LAYOUT=false
    DIR=$(dirname "$page_file")
    if [ -f "$DIR/layout.tsx" ] || [ -f "$DIR/layout.jsx" ]; then
      HAS_LAYOUT=true
    fi

    ROUTE_ENTRY=$(jq -n \
      --arg path "/$CLEAN_PATH" \
      --argjson isDynamic "$IS_DYNAMIC" \
      --arg dynamicType "$DYNAMIC_TYPE" \
      --argjson hasLayout "$HAS_LAYOUT" \
      '{path: $path, isDynamic: $isDynamic, dynamicType: $dynamicType, hasLayout: $hasLayout, inMenu: false}')

    ROUTES_JSON=$(echo "$ROUTES_JSON" | jq --argjson entry "$ROUTE_ENTRY" '. + [$entry]')

  done < <(find "$ENTRY_DIR" \( -name "page.tsx" -o -name "page.jsx" \) 2>/dev/null | sort)

elif [ "$FRAMEWORK" = "nextjs-pages-router" ]; then
  while IFS= read -r page_file; do
    route_path="${page_file#"$ENTRY_DIR"}"
    route_path="${route_path%.tsx}"
    route_path="${route_path%.jsx}"

    # Skip special files and api directory
    if [[ "$route_path" == _* ]] || [[ "$route_path" == api/* ]] || [[ "$route_path" == */api/* ]]; then
      continue
    fi

    # index → /
    route_path=$(echo "$route_path" | sed 's|/index$||' | sed 's|^index$||')

    IS_DYNAMIC=false
    DYNAMIC_TYPE="none"
    if [[ "$route_path" == *"[..."*"]"* ]]; then
      IS_DYNAMIC=true
      DYNAMIC_TYPE="catch-all"
    elif [[ "$route_path" == *"["*"]"* ]]; then
      IS_DYNAMIC=true
      DYNAMIC_TYPE="param"
    fi

    ROUTE_ENTRY=$(jq -n \
      --arg path "/$route_path" \
      --argjson isDynamic "$IS_DYNAMIC" \
      --arg dynamicType "$DYNAMIC_TYPE" \
      '{path: $path, isDynamic: $isDynamic, dynamicType: $dynamicType, hasLayout: false, inMenu: false}')

    ROUTES_JSON=$(echo "$ROUTES_JSON" | jq --argjson entry "$ROUTE_ENTRY" '. + [$entry]')

  done < <(find "$ENTRY_DIR" \( -name "*.tsx" -o -name "*.jsx" \) -not -name "_*" 2>/dev/null | sort)

elif [ "$FRAMEWORK" = "react-router" ]; then
  # Extract path definitions from router config files
  ROUTER_FILES=$(grep -rl 'createBrowserRouter\|<Route\|useRoutes' src/ 2>/dev/null || true)

  if [ -n "$ROUTER_FILES" ]; then
    # macOS-compatible: extract path="..." or path: "..." patterns
    PATHS=$(grep -oh 'path[=:] *["'"'"'][^"'"'"']*["'"'"']' $ROUTER_FILES 2>/dev/null \
      | sed 's/path[=:] *["'"'"']//;s/["'"'"']$//' | sort -u || true)

    while IFS= read -r route_path; do
      [ -z "$route_path" ] && continue

      IS_DYNAMIC=false
      if [[ "$route_path" == *":"* ]] || [[ "$route_path" == *"*"* ]]; then
        IS_DYNAMIC=true
      fi

      ROUTE_ENTRY=$(jq -n \
        --arg path "$route_path" \
        --argjson isDynamic "$IS_DYNAMIC" \
        '{path: $path, isDynamic: $isDynamic, dynamicType: "none", hasLayout: false, inMenu: false}')

      ROUTES_JSON=$(echo "$ROUTES_JSON" | jq --argjson entry "$ROUTE_ENTRY" '. + [$entry]')
    done <<< "$PATHS"
  fi
fi

# ================================================================
# S3: 交叉比對 Menu / Navigation
# ================================================================
MENU_SOURCE=""
TREE_JSON="[]"
WARNINGS_JSON="[]"

# --- Tree extraction via Node.js ---
# Uses bracket-counting + Function() eval to parse TS/JS array literals.
# Strips `as const` and type assertions before eval.
extract_tree_from_ts() {
  local file="$1"
  node -e "
    const fs = require('fs');
    const content = fs.readFileSync(process.argv[1], 'utf8');

    const startMatch = content.match(/(?:menuData|menu|navigation)\s*(?::\s*\w+(?:\[\])?\s*)?=\s*\[/);
    if (!startMatch) { console.log('[]'); process.exit(0); }

    const startIdx = startMatch.index + startMatch[0].length - 1;
    let depth = 0, endIdx = -1;
    for (let i = startIdx; i < content.length; i++) {
      if (content[i] === '[') depth++;
      else if (content[i] === ']') { depth--; if (depth === 0) { endIdx = i; break; } }
    }
    if (endIdx === -1) { console.log('[]'); process.exit(0); }

    let arr = content.slice(startIdx, endIdx + 1);
    // Strip TypeScript-only syntax that breaks eval
    arr = arr.replace(/\bas\s+\w+/g, '');         // 'as const', 'as MenuItem[]'
    arr = arr.replace(/<[^>]+>/g, '');             // generic type params
    arr = arr.replace(/!(?=[.\[])/g, '');          // non-null assertions

    try {
      const parsed = new Function('return ' + arr)();
      console.log(JSON.stringify(parsed));
    } catch(e) {
      console.error('Tree extraction failed:', e.message);
      console.log('[]');
    }
  " "$file" 2>/dev/null || echo "[]"
}

# --- Find menu definition files ---
# Exclude: type definitions, page consumers, test files, API routes, components
EXCLUDED='types\|\.d\.ts\|__tests__\|page\.tsx\|layout\.tsx\|/api/\|\.test\.\|\.spec\.'

# Priority 1: file named getMenu.ts / menu.ts (most conventional)
MENU_DATA_FILES=$(find src/ \( -name "getMenu.ts" -o -name "getMenu.tsx" -o -name "getMenu.js" -o -name "menu.ts" -o -name "menu.js" \) 2>/dev/null \
  | grep -v "$EXCLUDED" | head -5 || true)

# Priority 2: files with menuData or navItems array literal
if [ -z "$MENU_DATA_FILES" ]; then
  MENU_DATA_FILES=$(grep -rl 'menuData' src/ 2>/dev/null \
    | grep -v "$EXCLUDED" \
    | xargs grep -l '\[' 2>/dev/null | head -5 || true)
fi

# Priority 3: files with navigation array assignment
if [ -z "$MENU_DATA_FILES" ]; then
  MENU_DATA_FILES=$(grep -rl 'navigation.*=.*\[' src/ 2>/dev/null \
    | grep -v "$EXCLUDED" | head -5 || true)
fi

MENU_FILES="$MENU_DATA_FILES"

if [ -n "$MENU_FILES" ]; then
  MENU_SOURCE=$(echo "$MENU_FILES" | head -1)

  # Extract tree structure from source
  TREE_JSON=$(extract_tree_from_ts "$MENU_SOURCE")

  # Extract id values (macOS-compatible grep, no -P flag)
  MENU_IDS=$(grep -oh "id: *['\"][^'\"]*['\"]" $MENU_FILES 2>/dev/null \
    | sed "s/id: *['\"]//;s/['\"]$//" | sort -u || true)

  # Build id→label lookup from tree (for enriching routes)
  LABEL_MAP="{}"
  if [ "$TREE_JSON" != "[]" ]; then
    LABEL_MAP=$(echo "$TREE_JSON" | node -e "
      const data = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      const map = {};
      function walk(nodes) {
        for (const n of nodes) {
          if (n.id && n.label) map[n.id] = n.label;
          if (n.children) walk(n.children);
        }
      }
      walk(data);
      console.log(JSON.stringify(map));
    " 2>/dev/null || echo "{}")
  fi

  # Check if we have a catch-all route
  HAS_CATCHALL=$(echo "$ROUTES_JSON" | jq '[.[] | select(.dynamicType == "catch-all")] | length')

  if [ -n "$MENU_IDS" ]; then
    # Collect all menu IDs first, then batch-process to avoid duplicates
    SEEN_IDS=""

    while IFS= read -r menu_id; do
      [ -z "$menu_id" ] && continue

      # Dedup
      if echo "$SEEN_IDS" | grep -qx "$menu_id" 2>/dev/null; then
        continue
      fi
      SEEN_IDS="${SEEN_IDS}
${menu_id}"

      MATCH_PATH="/$menu_id"
      LABEL=$(echo "$LABEL_MAP" | jq -r --arg id "$menu_id" '.[$id] // ""')

      # Try exact match against filesystem routes
      FOUND=$(echo "$ROUTES_JSON" | jq --arg p "$MATCH_PATH" '[.[] | select(.path == $p)] | length')

      if [ "$FOUND" -gt 0 ]; then
        # Exact static route match
        ROUTES_JSON=$(echo "$ROUTES_JSON" | jq --arg p "$MATCH_PATH" --arg label "$LABEL" '
          map(if .path == $p then .inMenu = true | .label = $label else . end)')
      elif [ "$HAS_CATCHALL" -gt 0 ]; then
        # Catch-all covers this menu entry — add as resolved virtual route
        VIRTUAL_ROUTE=$(jq -n \
          --arg path "$MATCH_PATH" \
          --arg label "$LABEL" \
          '{path: $path, isDynamic: false, dynamicType: "resolved-by-catch-all", hasLayout: false, inMenu: true, label: $label}')
        ROUTES_JSON=$(echo "$ROUTES_JSON" | jq --argjson entry "$VIRTUAL_ROUTE" '. + [$entry]')
      else
        # No route covers this menu entry
        WARNING=$(jq -n --arg id "$menu_id" --arg label "$LABEL" \
          '{"type": "orphanMenuEntry", "id": $id, "label": $label}')
        WARNINGS_JSON=$(echo "$WARNINGS_JSON" | jq --argjson w "$WARNING" '. + [$w]')
      fi
    done <<< "$MENU_IDS"
  fi
fi

# ================================================================
# S4: 組裝 JSON 輸出
# ================================================================
ROUTE_COUNT=$(echo "$ROUTES_JSON" | jq 'length')
MENU_MATCH_COUNT=$(echo "$ROUTES_JSON" | jq '[.[] | select(.inMenu == true)] | length')
UNMAPPED_COUNT=$(echo "$ROUTES_JSON" | jq '[.[] | select(.inMenu == false)] | length')
ORPHAN_COUNT=$(echo "$WARNINGS_JSON" | jq 'length')

OUTPUT=$(jq -n \
  --arg framework "$FRAMEWORK" \
  --arg scannedAt "$TODAY" \
  --arg entryDir "$ENTRY_DIR" \
  --arg menuSource "$MENU_SOURCE" \
  --argjson routes "$ROUTES_JSON" \
  --argjson tree "$TREE_JSON" \
  --argjson warnings "$WARNINGS_JSON" \
  '{
    meta: {
      framework: $framework,
      scannedAt: $scannedAt,
      entryDir: $entryDir,
      menuSource: (if $menuSource == "" then null else $menuSource end)
    },
    routes: $routes,
    tree: $tree,
    warnings: $warnings
  }')

echo "$OUTPUT" | jq .

# ================================================================
# Summary to stderr
# ================================================================
echo "" >&2
echo "=== Sitemap Scan Complete ===" >&2
echo "Framework: $FRAMEWORK" >&2
echo "Entry dir: $ENTRY_DIR" >&2
echo "Menu source: ${MENU_SOURCE:-(not found)}" >&2
echo "Routes scanned: $ROUTE_COUNT" >&2
echo "  In menu: $MENU_MATCH_COUNT" >&2
echo "  Unmapped (auth/util pages): $UNMAPPED_COUNT" >&2
echo "Orphan menu entries: $ORPHAN_COUNT" >&2
echo "Tree nodes (top-level): $(echo "$TREE_JSON" | jq 'length')" >&2
echo "=============================" >&2
