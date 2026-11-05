#!/bin/bash
# Check the documentation against itself and against the code.
#
#   scripts/check-docs.sh [path/to/calmtile-binary]
#
# 1. every relative link and every #anchor in every tracked .md file points at something that exists;
# 2. every top-level config key of `calmtile --print-config` has a row in docs/manual.md;
# 3. every command-line switch handled in Sources/calmtile/main.swift is named in docs/manual.md.
#
# Step 2 needs a built binary (default build/calmtile.app/Contents/MacOS/calmtile); without one it is skipped
# with a notice. The binary is called directly, never through `open`. Exit status 1 when anything is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN="${1:-build/calmtile.app/Contents/MacOS/calmtile}"
FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=1; }

# --- 1. links and anchors -------------------------------------------------------------------------------
FILES=$(git ls-files '*.md')
python3 -I - $FILES <<'PY' || FAIL=1
import os, re, sys

def slug(h):
    # GitHub's rule: lower case, drop everything but letters, digits, space, '-' and '_', spaces become '-'.
    h = re.sub(r"`", "", h.strip().lower())
    h = re.sub(r"[^\w\- ]", "", h)
    return h.replace(" ", "-")

def anchors(path):
    out, seen, fence = set(), {}, False
    for line in open(path, encoding="utf-8"):
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        m = None if fence else re.match(r"#{1,6}\s+(.*?)\s*#*\s*$", line)
        if m:
            s = slug(re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", m.group(1)))
            n = seen.get(s, 0)
            seen[s] = n + 1
            out.add(s if n == 0 else f"{s}-{n}")
    return out

bad = 0
cache = {}
for md in sys.argv[1:]:
    fence = False
    for no, line in enumerate(open(md, encoding="utf-8"), 1):
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        line = re.sub(r"`[^`]*`", "", line)       # inline code is not a link
        for target in re.findall(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)", line):
            if re.match(r"[a-z][a-z0-9+.-]*:", target):   # https:, mailto:
                continue
            path, _, frag = target.partition("#")
            dest = md if path == "" else os.path.normpath(os.path.join(os.path.dirname(md), path))
            if not os.path.exists(dest):
                print(f"FAIL: {md}:{no}: missing file {target}", file=sys.stderr); bad += 1; continue
            if frag and dest.endswith(".md"):
                if dest not in cache:
                    cache[dest] = anchors(dest)
                if frag not in cache[dest]:
                    print(f"FAIL: {md}:{no}: missing anchor {target}", file=sys.stderr); bad += 1
sys.exit(1 if bad else 0)
PY

# --- 2. config keys -------------------------------------------------------------------------------------
if [ -x "$BIN" ]; then
  KEYS=$(HOME=$(mktemp -d) "$BIN" --print-config 2>/dev/null | python3 -I -c '
import json, sys
print("\n".join(json.load(sys.stdin).keys()))')
  for k in $KEYS; do
    grep -q "\`$k\`" docs/manual.md || fail "config key $k is not in docs/manual.md"
  done
else
  echo "note: $BIN not built, config keys not checked" >&2
fi

# --- 3. switches ----------------------------------------------------------------------------------------
for s in $(grep -oE '"--[a-z-]+"' Sources/calmtile/main.swift | tr -d '"' | sort -u); do
  grep -q -- "$s" docs/manual.md || fail "switch $s is not in docs/manual.md"
done

[ "$FAIL" = 0 ] && echo "docs OK"
exit "$FAIL"
