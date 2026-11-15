#!/bin/bash
# Copies every non-system dylib that the given binaries need (recursively) into LIBDIR and rewrites the
# load commands to @rpath, so the app runs on Macs without Homebrew.
# Usage: bundle-dylibs.sh <libdir> <binary-or-dylib>...
set -euo pipefail
LIBDIR="$1"; shift
mkdir -p "$LIBDIR"

is_external() { [[ "$1" == /opt/homebrew/* || "$1" == /usr/local/* ]]; }

deps_of() { otool -L "$1" | tail -n +2 | awk '{print $1}'; }

queue=("$@")
for f in "$LIBDIR"/*.dylib; do [ -f "$f" ] && [ ! -L "$f" ] && queue+=("$f"); done
seen=" "

while [ ${#queue[@]} -gt 0 ]; do
  file="${queue[0]}"; queue=("${queue[@]:1}")
  [[ "$seen" == *" $file "* ]] && continue
  seen+="$file "
  chmod u+w "$file"
  for dep in $(deps_of "$file"); do
    # Homebrew libraries may refer to each other as @rpath/<name> or @loader_path/<name>.
    if [[ "$dep" == @rpath/* || "$dep" == @loader_path/* ]]; then
      name="$(basename "$dep")"
      if [ ! -f "$LIBDIR/$name" ]; then
        found="$(ls /opt/homebrew/lib/"$name" /opt/homebrew/opt/*/lib/"$name" 2>/dev/null | head -1 || true)"
        if [ -n "$found" ]; then
          cp -L "$found" "$LIBDIR/$name"
          chmod u+w "$LIBDIR/$name"
          install_name_tool -id "@rpath/$name" "$LIBDIR/$name" 2>/dev/null
          install_name_tool -add_rpath "@loader_path" "$LIBDIR/$name" 2>/dev/null || true
          queue+=("$LIBDIR/$name")
        fi
      fi
      [[ "$dep" == @loader_path/* ]] && install_name_tool -change "$dep" "@rpath/$name" "$file" 2>/dev/null
      continue
    fi
    if is_external "$dep"; then
      name="$(basename "$dep")"
      target="$LIBDIR/$name"
      if [ ! -f "$target" ]; then
        cp -L "$dep" "$target"
        chmod u+w "$target"
        install_name_tool -id "@rpath/$name" "$target" 2>/dev/null
        install_name_tool -add_rpath "@loader_path" "$target" 2>/dev/null || true
        queue+=("$target")
      fi
      install_name_tool -change "$dep" "@rpath/$name" "$file" 2>/dev/null
    fi
  done
done

# Anything still pointing outside the bundle, or an @rpath library that is missing, is an error.
bad=0
for f in "$@" "$LIBDIR"/*.dylib; do
  [ -L "$f" ] && continue
  for dep in $(deps_of "$f" | grep '^@rpath/' || true); do
    [ -f "$LIBDIR/$(basename "$dep")" ] || { echo "missing: $dep (needed by $f)"; bad=1; }
  done
done
for f in "$@" "$LIBDIR"/*.dylib; do
  [ -L "$f" ] && continue
  if deps_of "$f" | grep -qE '^(/opt/homebrew|/usr/local)/'; then
    echo "still external: $f"; deps_of "$f" | grep -E '^(/opt/homebrew|/usr/local)/'; bad=1
  fi
done
exit $bad
