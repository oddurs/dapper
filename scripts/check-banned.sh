#!/usr/bin/env bash
# Banned constructs in src/. Each rule cites the decision in docs/plan.md that
# motivates it. Line-based, so a match inside a comment or string still fails —
# restructure or reword rather than adding an exception.
set -uo pipefail

fail=0

ban() {
  local pattern=$1 decision=$2 reason=$3
  local hits
  hits=$(grep -rnE "$pattern" src/ 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "FAIL [$decision] $reason"
    echo "$hits" | sed 's/^/    /'
    echo
    fail=1
  fi
}

# S9 — measured to differ between Erlang and JavaScript. dapper/format owns
# every float that reaches output.
ban '\bfloat\.to_string\b'  S9 'float.to_string diverges across targets; use dapper/format'
ban '\bstring\.inspect\b'   S9 'string.inspect diverges across targets; use an explicit formatter'

# P5 — dict.keys returns different orders on Erlang and JavaScript. Ordering
# must come from an explicit List.
ban '\bdict\.(keys|values|to_list|fold|map_values|each)\b' P5 \
  'Dict iteration order differs across targets; carry order in a List'

# M3 definition of done — render and validate are total.
ban '\blet assert\b' M3 'let assert is partial; return a Result or handle the case'
ban '^[^/]*\bpanic\b'  M3 'panic is partial; return a Result or handle the case'
ban '^[^/]*\btodo\b'   M3 'todo is partial; implement it or leave the module out of src/'

if [ "$fail" -ne 0 ]; then
  echo "banned constructs found in src/"
  exit 1
fi

echo "check-banned: clean"
