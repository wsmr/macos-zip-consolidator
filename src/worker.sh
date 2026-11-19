#!/bin/bash
# ZIP Extract & Consolidate worker (called by the AppleScript wrapper)
# usage: worker.sh MODE SRC DEST LISTFILE WORK     (MODE = scan | run)
MODE="$1"; SRC="$2"; DEST="$3"; LISTFILE="$4"; WORK="$5"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
# UTF-8 locale so Sinhala / Tamil / any non-ASCII file names are kept intact
if locale -a 2>/dev/null | grep -qi '^en_US\.utf-\{0,1\}8$'; then export LC_ALL=en_US.UTF-8
elif locale -a 2>/dev/null | grep -qi '^c\.utf-\{0,1\}8$'; then export LC_ALL=C.UTF-8; fi

IS_MAC=0; [ "$(uname -s)" = "Darwin" ] && IS_MAC=1
fsize()  { if [ $IS_MAC = 1 ]; then stat -f%z "$1" 2>/dev/null; else stat -c%s "$1" 2>/dev/null; fi; }
fmtime() { if [ $IS_MAC = 1 ]; then stat -f%m "$1" 2>/dev/null; else stat -c%Y "$1" 2>/dev/null; fi; }
lower()  { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# ---------- tool detection ----------
SZ=""; SZ_VER=""
for c in 7zz 7zzs 7z; do
  p=$(command -v "$c" 2>/dev/null)
  if [ -n "$p" ]; then SZ="$p"; break; fi
done
[ -n "$SZ" ] && SZ_VER=$("$SZ" 2>&1 </dev/null | grep -m1 -i '7-zip' | tr -d '\r')
UNAR=$(command -v unar 2>/dev/null)
DITTO=$(command -v ditto 2>/dev/null)
UNZIP=$(command -v unzip 2>/dev/null)
ZIPB=$(command -v zip 2>/dev/null)
BSDTAR=""; if tar --version 2>/dev/null | grep -qi bsdtar; then BSDTAR=$(command -v tar); fi
BREW=$(command -v brew 2>/dev/null)

mkdir -p "$WORK" 2>/dev/null
: > "$WORK/issues.tsv"

issue() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$WORK/issues.tsv"; }
status() { printf 'STEP|%s|%s|%s\n' "$1" "$2" "$3" > "$WORK/status.tmp"; mv -f "$WORK/status.tmp" "$WORK/status.txt"; }

nearest_existing() { d="$1"; while [ ! -d "$d" ] && [ "$d" != "/" ] && [ -n "$d" ]; do d=$(dirname "$d"); done; printf '%s' "$d"; }
free_bytes() { df -Pk "$(nearest_existing "$1")" 2>/dev/null | awk 'NR==2{printf "%.0f", $4*1024}'; }

has_ci() { [ -f "$1/$2.$3" ] || [ -f "$1/$2.$(printf '%s' "$3" | tr 'a-z' 'A-Z')" ]; }

# ---------- discovery ----------
discover() {
  : > "$WORK/plan.tsv"; : > "$WORK/warn.txt"; : > "$WORK/sigfiles.txt"
  if [ -n "$LISTFILE" ] && [ -s "$LISTFILE" ]; then cp "$LISTFILE" "$WORK/cand_raw.txt"
  else find "$SRC" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | sort > "$WORK/cand_raw.txt"; fi
  IGNORED=0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    n=$(basename "$f"); d=$(dirname "$f"); lc=$(lower "$n"); echo "$f" >> "$WORK/sigfiles.txt"
    case "$lc" in
      *.zip)
        base="${n%.*}"
        if has_ci "$d" "$base" z01; then
          i=1; parts=0
          while [ $i -le 99 ]; do
            nn=$(printf '%02d' $i)
            if has_ci "$d" "$base" "z$nn"; then parts=$i; i=$((i+1)); else break; fi
          done
          j=$((parts+1)); k=$((parts+3))
          while [ $j -le $k ] && [ $j -le 99 ]; do
            if has_ci "$d" "$base" "z$(printf '%02d' $j)"; then echo "Split ZIP \"$base\": part z$(printf '%02d' $((parts+1))) is missing (z$(printf '%02d' $j) exists)" >> "$WORK/warn.txt"; fi
            j=$((j+1))
          done
          for ((q=1;q<=parts;q++)); do for e in z$(printf '%02d' $q) Z$(printf '%02d' $q); do [ -f "$d/$base.$e" ] && echo "$d/$base.$e" >> "$WORK/sigfiles.txt"; done; done
          printf 'splitzip\t%s\t%s\n' "$f" "$((parts+1))" >> "$WORK/plan.tsv"
        else
          printf 'zip\t%s\t1\n' "$f" >> "$WORK/plan.tsv"
        fi ;;
      *.z[0-9][0-9])
        base="${n%.*}"; num="${lc##*.z}"
        if ! has_ci "$d" "$base" zip; then
          echo "Split ZIP \"$base\": part .z$num found but the final \"$base.zip\" is missing - cannot be extracted" >> "$WORK/warn.txt"
          issue PART_MISSING "$n" "final .zip part missing"
        elif [ "$num" != "01" ] && ! has_ci "$d" "$base" z01; then
          echo "Split ZIP \"$base\": .z01 is missing" >> "$WORK/warn.txt"
        fi ;;
      *.zip.[0-9][0-9][0-9]|*.7z.[0-9][0-9][0-9]|*.rar.[0-9][0-9][0-9]|*.tar.gz.[0-9][0-9][0-9]|*.tar.[0-9][0-9][0-9])
        base="${n%.*}"; num="${lc##*.}"
        if [ "$num" = "001" ]; then
          i=1; parts=0
          while [ $i -le 999 ]; do
            nn=$(printf '%03d' $i)
            if [ -f "$d/$base.$nn" ]; then parts=$i; echo "$d/$base.$nn" >> "$WORK/sigfiles.txt"; i=$((i+1)); else break; fi
          done
          if [ -f "$d/$base.$(printf '%03d' $((parts+2)))" ]; then echo "Multipart \"$base\": part $(printf '%03d' $((parts+1))) is missing" >> "$WORK/warn.txt"; issue PART_MISSING "$n" "part $(printf '%03d' $((parts+1))) missing"; fi
          printf 'splitnum\t%s\t%s\n' "$f" "$parts" >> "$WORK/plan.tsv"
        elif [ ! -f "$d/$base.001" ]; then
          echo "Multipart \"$base\": .001 is missing ($n found)" >> "$WORK/warn.txt"; issue PART_MISSING "$n" ".001 missing"
        fi ;;
      *.part[0-9]*.rar)
        pn=$(printf '%s' "$lc" | sed -E 's/.*\.part0*([0-9]+)\.rar$/\1/')
        if [ "$pn" = "1" ]; then printf 'other\t%s\t1\n' "$f" >> "$WORK/plan.tsv"; fi ;;
      *.7z|*.rar|*.tar|*.tgz|*.tar.gz|*.tar.bz2|*.tar.xz|*.tbz2|*.txz)
        printf 'other\t%s\t1\n' "$f" >> "$WORK/plan.tsv" ;;
      *) IGNORED=$((IGNORED+1)) ;;
    esac
  done < "$WORK/cand_raw.txt"

  # Google Drive numbered series (name-<stamp>-N-001.zip ...) : detect missing numbers
  awk -F'\t' '$1=="zip"||$1=="splitzip"{print $2}' "$WORK/plan.tsv" | while IFS= read -r p; do basename "$p"; done \
    | grep -E -- '-[0-9]{3}\.[zZ][iI][pP]$' \
    | sed -E 's/^(.*)-([0-9]{3})\.[zZ][iI][pP]$/\1\t\2/' > "$WORK/series.tsv"
  if [ -s "$WORK/series.tsv" ]; then
    awk -F'\t' '{k=$1; n=$2+0; cnt[k]++; if(n>mx[k])mx[k]=n; seen[k "," n]=1; keys[k]=1}
      END{for(k in keys){ if(mx[k]>cnt[k]){ miss=""; for(i=1;i<=mx[k];i++) if(!((k "," i) in seen)) miss=miss (miss==""?"":", ") sprintf("%03d",i);
        print "Download series \"" k "\" is missing part(s): " miss " (found " cnt[k] ", highest number " sprintf("%03d",mx[k]) ")" }}}' "$WORK/series.tsv" >> "$WORK/warn.txt"
    sed -n 's/^\(Download series.*\)$/\1/p' "$WORK/warn.txt" | while IFS= read -r w; do issue PART_MISSING "(zip series)" "$w"; done
  fi
}

# ---------- scan mode ----------
if [ "$MODE" = "scan" ]; then
  discover
  echo "SZ|$SZ|$SZ_VER"
  echo "UNAR|$UNAR"; echo "BREW|$BREW"
  echo "TAR|$BSDTAR"; echo "DITTO|$DITTO"; echo "UNZIP|$UNZIP"; echo "ZIP|$ZIPB"
  [ $IS_MAC = 1 ] && echo "MACOS|$(sw_vers -productVersion 2>/dev/null)"
  comp=0
  while IFS=$'\t' read -r kind path parts; do
    sz=$(fsize "$path"); [ -z "$sz" ] && sz=0
    echo "ARCH|$kind|$(basename "$path")|$parts|$sz"
    comp=$((comp+sz))
  done < "$WORK/plan.tsv"
  echo "COMP|$comp"; echo "FREE|$(free_bytes "$DEST")"; echo "IGN|$IGNORED"
  while IFS= read -r w; do echo "WARN|$w"; done < "$WORK/warn.txt"
  exit 0
fi

# ---------- run mode ----------
REPORT_NAME="issue_files_name_with_path.txt"
N_ARCH=0; N_OK=0; N_ISSUE_ARCH=0; N_SKIPPED=0; N_MERGED=0; N_DUPSAME=0; N_CONFLICT=0; N_BADFILES=0
FINISHED=0; CANCELLED=0; START_TS=$(date '+%Y-%m-%d %H:%M:%S')

safe_rm() { case "$1" in "$DEST"/.extract_staging_*|"$WORK"/*) [ -e "$1" ] && rm -rf -- "$1" ;; esac; }

finish() {
  [ $FINISHED = 1 ] && return; FINISHED=1
  for s in "$DEST"/.extract_staging_*; do [ -d "$s" ] && safe_rm "$s"; done
  # source-archive integrity check (nothing may have changed)
  if [ -s "$WORK/sig_before.txt" ]; then
    : > "$WORK/sig_after.txt"
    while IFS= read -r f; do printf '%s|%s|%s\n' "$f" "$(fsize "$f")" "$(fmtime "$f")" >> "$WORK/sig_after.txt"; done < "$WORK/sigfiles.txt"
    if ! cmp -s "$WORK/sig_before.txt" "$WORK/sig_after.txt"; then issue SOURCE_CHANGED "(source archives)" "An original archive changed size/date during processing - please check"; fi
  fi
  rdir="$SRC"; [ -w "$rdir" ] || rdir="$DEST"; [ -w "$rdir" ] || rdir="$HOME/Desktop"
  REPORT="$rdir/$REPORT_NAME"
  if [ -e "$REPORT" ]; then mv -f "$REPORT" "$rdir/issue_files_name_with_path_$(date '+%Y%m%d-%H%M%S').txt"; fi
  {
    echo "ZIP EXTRACT & CONSOLIDATE - ISSUE REPORT"
    echo "Started : $START_TS"
    echo "Ended   : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Source  : $SRC"
    echo "Output  : $DEST"
    echo "Tool    : ${SZ:-none (limited mode)} $SZ_VER"
    [ $CANCELLED = 1 ] && echo "STATUS  : CANCELLED BY USER - results are partial"
    echo "Original archives were NOT modified, moved or deleted."
    echo
    if [ ! -s "$WORK/issues.tsv" ]; then echo "No issues found."; else
      echo "=== ARCHIVE-LEVEL ISSUES (type | archive | detail) ==="
      awk -F'\t' '$1!="MISSING"&&$1!="TRUNCATED_OR_CORRUPT"&&$1!="CONFLICT_COPY"{print "[" $1 "] " $2 " | " $3}' "$WORK/issues.tsv"
      echo
      echo "=== FILE-LEVEL ISSUES (file path as inside the archive / Google Drive) ==="
      awk -F'\t' '$1=="MISSING"||$1=="TRUNCATED_OR_CORRUPT"{print "[" $1 "] " $3 "   (archive: " $2 ")"}' "$WORK/issues.tsv"
      echo
      echo "=== NAME CONFLICTS (different file with same name; both kept, nothing overwritten) ==="
      awk -F'\t' '$1=="CONFLICT_COPY"{print $3 "   (archive: " $2 ")"}' "$WORK/issues.tsv"
      echo
      echo "=== RE-DOWNLOAD LIST (one path per line) ==="
      awk -F'\t' '$1=="MISSING"||$1=="TRUNCATED_OR_CORRUPT"{print $3}' "$WORK/issues.tsv" | sort -u
    fi
  } > "$REPORT" 2>/dev/null
  {
    echo "archives=$N_ARCH"; echo "ok=$N_OK"; echo "issue_archives=$N_ISSUE_ARCH"; echo "skipped_done=$N_SKIPPED"
    echo "merged=$N_MERGED"; echo "dup_identical=$N_DUPSAME"; echo "conflicts=$N_CONFLICT"; echo "bad_files=$N_BADFILES"
    echo "issues=$(wc -l < "$WORK/issues.tsv" | tr -d ' ')"; echo "report=$REPORT"; echo "dest=$DEST"; echo "cancelled=$CANCELLED"
  } > "$WORK/summary.txt"
  printf 'DONE|0|finished\n' > "$WORK/status.tmp"; mv -f "$WORK/status.tmp" "$WORK/status.txt"
}
trap 'CANCELLED=1; exit 130' TERM INT HUP
trap finish EXIT

case "$DEST" in ""|"/") issue FATAL "(destination)" "invalid destination"; exit 2;; esac
mkdir -p "$DEST" 2>/dev/null
if [ ! -d "$DEST" ] || [ ! -w "$DEST" ]; then issue FATAL "(destination)" "Destination not writable: $DEST"; exit 2; fi
for s in "$DEST"/.extract_staging_*; do [ -d "$s" ] && safe_rm "$s"; done   # leftovers of an interrupted run (temp copies only)

discover
: > "$WORK/sig_before.txt"
while IFS= read -r f; do printf '%s|%s|%s\n' "$f" "$(fsize "$f")" "$(fmtime "$f")" >> "$WORK/sig_before.txt"; done < "$WORK/sigfiles.txt"
TOTAL=$(wc -l < "$WORK/plan.tsv" | tr -d ' ')
MARKER="$DEST/.completed_archives.txt"

unique_target() {
  t="$1"; dir=$(dirname "$t"); b=$(basename "$t")
  case "$b" in *.*) stem="${b%.*}"; ext=".${b##*.}";; *) stem="$b"; ext="";; esac
  i=1; while :; do c="$dir/$stem (conflict $i)$ext"; [ -e "$c" ] || break; i=$((i+1)); done
  printf '%s' "$c"
}

fallback_extract() {   # $1 archive  $2 staging ; returns 0 if something was extracted
  a="$1"; s="$2"
  for tool in unar bsdtar ditto unzip; do
    case "$tool" in
      unar)   [ -n "$UNAR" ]   && "$UNAR" -q -D -o "$s" "$a" </dev/null >> "$WORK/fb.log" 2>&1 ;;
      bsdtar) [ -n "$BSDTAR" ] && "$BSDTAR" -xf "$a" -C "$s" </dev/null >> "$WORK/fb.log" 2>&1 ;;
      ditto)  [ -n "$DITTO" ]  && "$DITTO" -x -k "$a" "$s" </dev/null >> "$WORK/fb.log" 2>&1 ;;
      unzip)  [ -n "$UNZIP" ]  && "$UNZIP" -o -q "$a" -d "$s" </dev/null >> "$WORK/fb.log" 2>&1 ;;
    esac
    rc=$?
    cnt=$(find "$s" -type f 2>/dev/null | head -1 | wc -l | tr -d ' ')
    FB_TOOL="$tool"; FB_RC=$rc
    if [ "$rc" = "0" ] && [ "$cnt" != "0" ]; then return 0; fi
    if [ "$cnt" != "0" ]; then return 0; fi   # partial result: caller flags it as unverified
  done
  return 1
}

process_archive() {  # kind path idx name
  kind="$1"; path="$2"; idx="$3"; name="$4"
  stg="$DEST/.extract_staging_$idx"; safe_rm "$stg"; mkdir -p "$stg"
  issues_before=$(wc -l < "$WORK/issues.tsv" | tr -d ' ')
  asz=$(fsize "$path"); amt=$(fmtime "$path")
  if [ -f "$MARKER" ] && grep -qxF -- "$name|$asz|$amt" "$MARKER"; then N_SKIPPED=$((N_SKIPPED+1)); safe_rm "$stg"; return; fi
  UNVERIFIED=0; : > "$WORK/expected.tsv"; : > "$WORK/badpaths.txt"; ERRSUMMARY=""
  USE_PATH="$path"; TMPCOMB=""

  if [ -n "$SZ" ]; then
    "$SZ" l -slt "$path" </dev/null > "$WORK/l.txt" 2>&1
    awk '/^----------$/{inent=1;next} !inent{next}
         /^Path = /{flush(); p=substr($0,8); sz=""; dir=0; next}
         /^Folder = /{dir=($0=="Folder = +")}
         /^Size = /{sz=substr($0,8)}
         /^$/{flush()}
         END{flush()}
         function flush(){ if(p!="" && !dir && sz!="" && p !~ /(^|\/)__MACOSX\// && p !~ /(^|\/)\.DS_Store$/) print sz "\t" p; p="" }' "$WORK/l.txt" > "$WORK/expected.tsv"
    if grep -q '^Encrypted = +' "$WORK/l.txt"; then
      issue ARCHIVE_ENCRYPTED "$name" "Password-protected archive - cannot extract automatically"; safe_rm "$stg"; return
    fi
    if [ ! -s "$WORK/expected.tsv" ]; then
      ERRSUMMARY=$(grep -E 'ERROR|Can not|Cannot|Unexpected|not archive|Headers|Wrong' "$WORK/l.txt" | head -2 | tr '\n' ' ')
      issue ARCHIVE_UNREADABLE "$name" "7-Zip could not read the file list. ${ERRSUMMARY}"
      UNVERIFIED=1
    else
      need=$(awk -F'\t' '{s+=$1} END{printf "%.0f", s*1.02+104857600}' "$WORK/expected.tsv"); free=$(free_bytes "$DEST")
      if awk -v a="$free" -v b="$need" 'BEGIN{exit !(a+0<b+0)}'; then
        issue ARCHIVE_NO_SPACE "$name" "Not enough free disk space (need about $((need/1048576)) MB, free $((free/1048576)) MB). Free space and run again."
        safe_rm "$stg"; return
      fi
      "$SZ" x -y -bd '-xr!__MACOSX' '-xr!.DS_Store' -o"$stg" "$path" </dev/null > "$WORK/x.txt" 2>&1
      grep -E '^ERROR' "$WORK/x.txt" | sed -E 's/^ERROR: ([^:]*) : (.*)$/\2/' | grep -v '^ERROR' > "$WORK/badpaths.txt"
      ERRSUMMARY=$(grep -E '^ERROR' "$WORK/x.txt" | head -3 | tr '\n' ' ')
    fi
  else
    UNVERIFIED=1
  fi

  if [ "$UNVERIFIED" = "1" ]; then
    # limited mode / unreadable listing: try the built-in extractors
    case "$kind" in
      splitzip) if [ -n "$ZIPB" ]; then TMPCOMB="$WORK/combined_$idx.zip"; "$ZIPB" -q -s 0 "$path" --out "$TMPCOMB" </dev/null >/dev/null 2>&1 && USE_PATH="$TMPCOMB"; fi ;;
      splitnum) base="${path%.001}"; TMPCOMB="$WORK/combined_$idx.bin"; cat "$base".[0-9][0-9][0-9] > "$TMPCOMB" 2>/dev/null && USE_PATH="$TMPCOMB" ;;
    esac
    : > "$WORK/fb.log"
    if fallback_extract "$USE_PATH" "$stg"; then
      if [ "$FB_RC" = "0" ] && [ "$FB_TOOL" != "unzip" ]; then
        UNVERIFIED=0   # tool finished with exit 0 (it checks CRCs itself) and keeps Unicode names
      else
        issue ARCHIVE_UNVERIFIED "$name" "Extracted with fallback tool ($FB_TOOL, exit $FB_RC) without per-file checking - files placed in _UNVERIFIED_FROM_ARCHIVES. Install 7-Zip (brew install sevenzip) and re-run."
      fi
    else
      issue ARCHIVE_FAILED "$name" "No extractor could read this archive (corrupt or incomplete download). $(head -2 "$WORK/fb.log" 2>/dev/null | tr '\n' ' ')"
      safe_rm "$stg"; [ -n "$TMPCOMB" ] && rm -f "$TMPCOMB"; return
    fi
    [ -n "$TMPCOMB" ] && rm -f "$TMPCOMB"
  else
    # ---- verify every expected file: present, right size, no reported error ----
    arch_bad=0
    while IFS=$'\t' read -r esz epath; do
      f="$stg/$epath"
      if [ ! -f "$f" ]; then issue MISSING "$name" "$epath"; arch_bad=$((arch_bad+1)); continue; fi
      if [ "$(fsize "$f")" != "$esz" ] || { [ -s "$WORK/badpaths.txt" ] && grep -qxF -- "$epath" "$WORK/badpaths.txt"; }; then
        issue TRUNCATED_OR_CORRUPT "$name" "$epath"; rm -f -- "$f"; arch_bad=$((arch_bad+1))
      fi
    done < "$WORK/expected.tsv"
    N_BADFILES=$((N_BADFILES+arch_bad))
    if [ $arch_bad -eq 0 ] && [ -n "$ERRSUMMARY" ]; then issue ARCHIVE_ERRORS "$name" "$ERRSUMMARY"; fi
  fi

  # ---- merge staging -> destination (never overwrite) ----
  MB="$DEST"
  if [ "$UNVERIFIED" = "1" ]; then MB="$DEST/_UNVERIFIED_FROM_ARCHIVES/$name"; mkdir -p "$MB"; fi
  find "$stg" -mindepth 1 -type d > "$WORK/stgdirs.txt" 2>/dev/null
  while IFS= read -r dd; do mkdir -p "$MB/${dd#"$stg"/}"; done < "$WORK/stgdirs.txt"
  find "$stg" -type f > "$WORK/stgfiles.txt" 2>/dev/null
  while IFS= read -r f; do
    rel="${f#"$stg"/}"; target="$MB/$rel"; mkdir -p "$(dirname "$target")"
    if [ ! -e "$target" ]; then
      if mv -- "$f" "$target"; then N_MERGED=$((N_MERGED+1)); else issue MERGE_FAILED "$name" "$rel"; fi
    elif [ -f "$target" ] && cmp -s -- "$f" "$target"; then
      N_DUPSAME=$((N_DUPSAME+1)); rm -f -- "$f"
    else
      alt=$(unique_target "$target")
      if mv -- "$f" "$alt"; then N_MERGED=$((N_MERGED+1)); N_CONFLICT=$((N_CONFLICT+1)); issue CONFLICT_COPY "$name" "${alt#"$DEST"/}"; else issue MERGE_FAILED "$name" "$rel"; fi
    fi
  done < "$WORK/stgfiles.txt"
  safe_rm "$stg"

  issues_after=$(wc -l < "$WORK/issues.tsv" | tr -d ' ')
  if [ "$issues_after" = "$issues_before" ] && [ "$UNVERIFIED" = "0" ]; then
    N_OK=$((N_OK+1)); echo "$name|$asz|$amt" >> "$MARKER"
  else
    N_ISSUE_ARCH=$((N_ISSUE_ARCH+1))
  fi
}

if [ "$TOTAL" = "0" ]; then issue NO_ARCHIVES "(none)" "No ZIP / split / multipart archives found in $SRC"; exit 0; fi

idx=0
while IFS=$'\t' read -r -u 3 kind path parts; do
  idx=$((idx+1)); N_ARCH=$((N_ARCH+1)); name=$(basename "$path")
  status "$idx" "$TOTAL" "$name"
  process_archive "$kind" "$path" "$idx" "$name"
done 3< "$WORK/plan.tsv"
exit 0
