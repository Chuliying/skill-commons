# Tiny assertion lib. Each test file is its own process; counters are per-process.
set -u
TESTS_PASS=0
TESTS_FAIL=0

assert_eq() { # expected actual msg
  if [ "$1" = "$2" ]; then TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $3";
  else TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL: $3 (expected '$1' got '$2')"; fi
}
assert_neq() { # a b msg
  if [ "$1" != "$2" ]; then TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $3";
  else TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL: $3 (both '$1')"; fi
}
assert_contains() { # haystack needle msg
  case "$1" in *"$2"*) TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $3";;
  *) TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL: $3 (missing '$2')";; esac
}
assert_not_contains() { # haystack needle msg
  case "$1" in *"$2"*) TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL: $3 (found '$2')";;
  *) TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $3";; esac
}
assert_file() { # path msg
  if [ -f "$1" ]; then TESTS_PASS=$((TESTS_PASS+1)); echo "  ok: $2";
  else TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL: $2 (no file $1)"; fi
}
fail() { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL: $1"; }
finish() { echo "  -> PASS=$TESTS_PASS FAIL=$TESTS_FAIL"; [ "$TESTS_FAIL" = 0 ]; }
