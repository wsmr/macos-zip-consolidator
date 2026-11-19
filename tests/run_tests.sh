#!/bin/bash
# Self-test for src/worker.sh. Needs: bash, zip, and 7zz or 7z. Works on macOS and Linux.
# Usage: bash tests/run_tests.sh
HERE="$(cd "$(dirname "$0")/.." && pwd)"
W="$HERE/src/worker.sh"
T="$(mktemp -d /tmp/zipconsol-test.XXXXXX)"; trap 'rm -rf "$T"' EXIT
command -v zip >/dev/null || { echo "need 'zip'"; exit 2; }
if command -v 7zz >/dev/null; then :; elif command -v 7z >/dev/null; then :; else echo "need 7zz or 7z"; exit 2; fi
sha() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

D="$T/data/Drive Folder"; S="$T/src"
mkdir -p "$D/01 Physics/Sub" "$D/02 Chem" "$D/Empty Dir" "$S" "$T/sp"
for i in 1 2 3 4 5 6; do head -c $((100000*i)) /dev/urandom > "$D/01 Physics/Sub/f$i.bin"; done
head -c 200000 /dev/urandom > "$D/02 Chem/සිංහල_ගොනුව.pdf"
head -c 300000 /dev/urandom > "$D/02 Chem/big.pdf"; echo hi > "$D/01 Physics/a.txt"
( cd "$T/data"
  zip -q -r "$S/Drive-20260930T025711Z-1-001.zip" "Drive Folder/01 Physics/Sub/f1.bin" "Drive Folder/01 Physics/Sub/f2.bin" "Drive Folder/Empty Dir"
  zip -q -r "$S/Drive-20260930T025711Z-1-002.zip" "Drive Folder/01 Physics/Sub/f3.bin" "Drive Folder/02 Chem/සිංහල_ගොනුව.pdf" "Drive Folder/01 Physics/a.txt"
  zip -q -r "$S/Drive-20260930T025711Z-1-004.zip" "Drive Folder/02 Chem/big.pdf" "Drive Folder/01 Physics/Sub/f4.bin" "Drive Folder/01 Physics/Sub/f5.bin"
  zip -q "$S/Drive-20260930T025711Z-1-005.zip" "Drive Folder/01 Physics/Sub/f6.bin" "Drive Folder/01 Physics/a.txt" )
dd if=/dev/urandom of="$S/Drive-20260930T025711Z-1-005.zip" bs=1 seek=5000 count=100 conv=notrunc 2>/dev/null   # corrupt data
head -c 3000000 /dev/urandom > "$T/sp/split.bin"; ( cd "$T/sp" && zip -q -s 1m "$S/Big.zip" split.bin )          # split zip
head -c 100000 "$S/Drive-20260930T025711Z-1-004.zip" > "$S/Trunc.zip"                                          # truncated download
( cd "$S" && sha ./* > "$T/before.sha" )

echo "== scan"
SCAN="$(bash "$W" scan "$S" "$S/Out" "" "$T/w_scan")"
check "series gap (003) is detected"   'echo "$SCAN" | grep -q "missing part(s): 003"'
check "split zip is recognised"        'echo "$SCAN" | grep -q "^ARCH|splitzip|Big.zip"'

echo "== run"
bash "$W" run "$S" "$S/Out" "" "$T/w_run" >/dev/null 2>&1
O="$S/Out/Drive Folder"; R="$S/issue_files_name_with_path.txt"
check "valid files extracted"          '[ -f "$O/01 Physics/Sub/f1.bin" ] && [ -f "$O/01 Physics/Sub/f5.bin" ]'
check "non-ASCII file name preserved"  '[ -f "$O/02 Chem/සිංහල_ගොනුව.pdf" ]'
check "empty folder preserved"         '[ -d "$O/Empty Dir" ]'
check "split zip extracted"            '[ -f "$S/Out/split.bin" ]'
check "corrupt file NOT in output"     '[ ! -f "$O/01 Physics/Sub/f6.bin" ]'
check "corrupt file listed in report"  'grep -q "f6.bin" "$R"'
check "report file exists"             '[ -f "$R" ]'
check "originals unchanged"            '! ( cd "$S" && sha -c "$T/before.sha" 2>&1 | grep -v ": OK" | grep -q . )'
check "no staging leftovers"           '! ls -a "$S/Out" | grep -q "extract_staging"'

echo "== conflict handling"
mkdir -p "$T/c/Drive Folder/01 Physics"; echo DIFFERENT > "$T/c/Drive Folder/01 Physics/a.txt"
( cd "$T/c" && zip -q "$S/Other.zip" "Drive Folder/01 Physics/a.txt" )
bash "$W" run "$S" "$S/Out" "" "$T/w_run2" >/dev/null 2>&1
check "original a.txt kept"              'grep -q "^hi$" "$O/01 Physics/a.txt"'
check "different copy saved as conflict" 'ls "$O/01 Physics" | grep -q "a (conflict 1).txt"'

echo; echo "Passed: $PASS   Failed: $FAIL"; [ $FAIL -eq 0 ]
