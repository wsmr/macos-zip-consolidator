-- ======================================================================
--  ZIP Extract & Consolidate   (for FastScripts / Script Editor)
--  Extracts ZIP downloads (Google Drive folder downloads, split / multipart
--  ZIPs ...) into ONE consolidated folder, never touching the originals.
--
--  HOW TO USE
--    1. In Finder open the folder that holds the downloaded ZIP files
--       (or select that folder, or select just the ZIP files you want).
--    2. Run this script from FastScripts.
--    3. Check the summary and the file  issue_files_name_with_path.txt
--       that is written next to your ZIP files.
--
--  RECOMMENDED (one time):   brew install sevenzip
--       7-Zip skips damaged files instead of aborting, and verifies every
--       file. Without it the script runs in a limited mode.
-- ======================================================================

property dlgTitle : "ZIP Extract & Consolidate"
property reportName : "issue_files_name_with_path.txt"
property defaultDestName : "Consolidated_Extracted"

on run
	try
		my mainFlow()
	on error errMsg number errNum
		if errNum is not -128 then
			try
				display dialog "The script stopped unexpectedly:" & return & return & errMsg & " (error " & errNum & ")" & return & return & "Your original ZIP files were not modified." buttons {"OK"} default button "OK" with icon stop with title dlgTitle
			end try
		end if
	end try
end run

on mainFlow()
	-- ---------- 0. macOS check ----------
	set majorV to 0
	set minorV to 0
	try
		set majorV to (do shell script "sw_vers -productVersion | cut -d. -f1") as integer
		set minorV to (do shell script "sw_vers -productVersion | cut -d. -f2") as integer
	end try
	if majorV is 10 and minorV < 13 then
		display dialog "This script is written for macOS 10.13 or newer. It may still work on your Mac, but it has not been tested on this version." buttons {"Cancel", "Continue anyway"} default button "Continue anyway" with icon caution with title dlgTitle
	end if
	
	-- ---------- 1. what should be processed? ----------
	set pick to my pickSource()
	set srcPath to item 1 of pick
	set selFiles to item 2 of pick
	set destPath to srcPath & "/" & defaultDestName
	
	-- ---------- 2. write the helper (worker) script to a temp folder ----------
	set workDir to do shell script "mktemp -d /tmp/zipconsol.XXXXXX"
	set workerPath to workDir & "/worker.sh"
	set w to my buildWorker()
	do shell script "printf '%s' " & quoted form of w & " > " & quoted form of workerPath
	set listFile to ""
	if (count of selFiles) > 0 then
		set listFile to workDir & "/selected.txt"
		set cmd to "printf '%s\\n'"
		repeat with p in selFiles
			set cmd to cmd & " " & quoted form of (contents of p)
		end repeat
		do shell script cmd & " > " & quoted form of listFile
	end if
	
	-- ---------- 3. scan (read-only) and pre-flight checks ----------
	set scanOut to do shell script "/bin/bash " & quoted form of workerPath & " scan " & quoted form of srcPath & " " & quoted form of destPath & " " & quoted form of listFile & " " & quoted form of (workDir & "/scan") as «class utf8»
	set szPath to ""
	set szVer to ""
	set brewPath to ""
	set unarPath to ""
	set archCount to 0
	set nZip to 0
	set nSplit to 0
	set nOther to 0
	set compBytes to "0"
	set freeBytes to "0"
	set warnList to {}
	set nameList to {}
	repeat with ln in paragraphs of scanOut
		set ln to contents of ln
		if ln begins with "SZ|" then
			set f to my splitBy(ln, "|")
			if (count of f) ≥ 2 then set szPath to item 2 of f
			if (count of f) ≥ 3 then set szVer to item 3 of f
		else if ln begins with "BREW|" then
			set brewPath to my afterBar(ln)
		else if ln begins with "UNAR|" then
			set unarPath to my afterBar(ln)
		else if ln begins with "ARCH|" then
			set f to my splitBy(ln, "|")
			set archCount to archCount + 1
			set k to item 2 of f
			if k is "zip" then
				set nZip to nZip + 1
			else if k is "splitzip" or k is "splitnum" then
				set nSplit to nSplit + 1
			else
				set nOther to nOther + 1
			end if
			if (count of nameList) < 6 then set end of nameList to item 3 of f
		else if ln begins with "COMP|" then
			set compBytes to my afterBar(ln)
		else if ln begins with "FREE|" then
			set freeBytes to my afterBar(ln)
		else if ln begins with "WARN|" then
			set end of warnList to my afterBar(ln)
		end if
	end repeat
	
	if szPath is "" then
		set installCmd to "brew install sevenzip"
		set installHelp to "Install it once in Terminal:" & return & return & installCmd
		if brewPath is "" then set installHelp to "Homebrew is not installed. First install Homebrew from https://brew.sh , then run:" & return & return & installCmd & return & return & "(Alternative: download the command-line 7-Zip for macOS (7zz) from https://www.7-zip.org and copy it to /usr/local/bin)"
		set r to display dialog "7-Zip (7zz) was not found on this Mac." & return & return & "It is strongly recommended: it is the only tool that can reliably open damaged or incomplete Google Drive ZIPs, skip bad files, and read split/multipart ZIPs." & return & return & installHelp & return & return & "You can also continue in LIMITED mode (built-in macOS tools, no per-file verification; files that cannot be verified go to a separate _UNVERIFIED_FROM_ARCHIVES folder)." buttons {"Cancel", "Copy install command", "Continue (limited mode)"} default button "Copy install command" with icon caution with title dlgTitle
		if button returned of r is "Copy install command" then
			set the clipboard to installCmd
			display dialog "The install command was copied to the clipboard." & return & "Paste it into Terminal, wait until it finishes, then run this script again." buttons {"OK"} default button "OK" with title dlgTitle
			my cleanupTemp(workDir)
			return
		end if
	end if
	
	if archCount is 0 then
		set msg to "No ZIP / split / multipart archives were found in:" & return & srcPath & return & return & "Open the folder that contains the downloads in Finder (or select the ZIP files) and run again."
		if (count of warnList) > 0 then set msg to msg & return & return & "Notes:" & return & my joinLines(warnList, 6)
		display dialog msg buttons {"OK"} default button "OK" with icon caution with title dlgTitle
		my cleanupTemp(workDir)
		return
	end if
	
	-- ---------- 4. confirm ----------
	set lowSpace to false
	try
		set lowSpace to ((do shell script "awk -v a=" & freeBytes & " -v b=" & compBytes & " 'BEGIN{print (a < b*1.3) ? 1 : 0}'") is "1")
	end try
	repeat
		set msg to "Folder: " & srcPath & return & "Archives found: " & archCount & "  (" & nZip & " ZIP, " & nSplit & " split/multipart, " & nOther & " other)" & return & "Size of archives: " & my humanSize(compBytes) & "    Free space: " & my humanSize(freeBytes) & return
		if szPath is "" then
			set msg to msg & "Mode: LIMITED (7-Zip not installed)" & return
		else
			set msg to msg & "Mode: full (" & szVer & ")" & return
		end if
		set msg to msg & "Consolidated output folder:" & return & destPath & return
		if lowSpace then set msg to msg & return & "WARNING: free disk space looks low for the extraction (usually needs about the size of the archives or more)." & return
		if (count of warnList) > 0 then set msg to msg & return & "WARNINGS:" & return & my joinLines(warnList, 8) & return
		set msg to msg & return & "Original ZIP files are only read - never modified, moved or deleted. Existing files in the output folder are never overwritten."
		set r to display dialog msg buttons {"Cancel", "Change Output Folder...", "Start"} default button "Start" with title dlgTitle
		if button returned of r is "Start" then exit repeat
		set chosen to POSIX path of (choose folder with prompt "Choose the folder that will receive the consolidated files:")
		set destPath to do shell script "p=" & quoted form of chosen & "; printf '%s' \"${p%/}\""
		set scanOut2 to do shell script "/bin/bash " & quoted form of workerPath & " scan " & quoted form of srcPath & " " & quoted form of destPath & " " & quoted form of listFile & " " & quoted form of (workDir & "/scan2")
		repeat with ln in paragraphs of scanOut2
			if (contents of ln) begins with "FREE|" then
				set freeBytes to my afterBar(contents of ln)
				try
					set lowSpace to ((do shell script "awk -v a=" & freeBytes & " -v b=" & compBytes & " 'BEGIN{print (a < b*1.3) ? 1 : 0}'") is "1")
				end try
			end if
		end repeat
	end repeat
	
	try
		do shell script "mkdir -p " & quoted form of destPath & " && test -w " & quoted form of destPath
	on error
		display dialog "The output folder cannot be created or is not writable:" & return & destPath & return & return & "Nothing was changed." buttons {"OK"} default button "OK" with icon stop with title dlgTitle
		my cleanupTemp(workDir)
		return
	end try
	
	-- ---------- 5. run the worker in the background and show progress ----------
	set runWork to workDir & "/run"
	set pid to do shell script "nohup /bin/bash " & quoted form of workerPath & " run " & quoted form of srcPath & " " & quoted form of destPath & " " & quoted form of listFile & " " & quoted form of runWork & " > " & quoted form of (workDir & "/worker.log") & " 2>&1 & echo $!"
	set wasCancelled to false
	try
		set progress total steps to archCount
		set progress completed steps to 0
		set progress description to "Extracting and consolidating..."
		set progress additional description to "Starting..."
	end try
	try
		repeat
			delay 1
			set st to ""
			try
				set st to do shell script "cat " & quoted form of (runWork & "/status.txt") & " 2>/dev/null; true"
			end try
			if st begins with "DONE" then exit repeat
			if st begins with "STEP|" then
				set f to my splitBy(st, "|")
				if (count of f) ≥ 4 then
					try
						set progress completed steps to ((item 2 of f) as integer) - 1
						set progress additional description to "(" & (item 2 of f) & " of " & (item 3 of f) & ")  " & (item 4 of f)
					end try
				end if
			end if
			set alive to do shell script "kill -0 " & pid & " 2>/dev/null && echo 1 || echo 0"
			if alive is "0" then
				delay 1
				exit repeat
			end if
		end repeat
	on error errMsg number errNum
		if errNum is -128 then
			set wasCancelled to true
			try
				do shell script "pkill -TERM -P " & pid & " 2>/dev/null; kill -TERM " & pid & " 2>/dev/null; true"
			end try
			repeat 20 times
				delay 1
				set st to ""
				try
					set st to do shell script "cat " & quoted form of (runWork & "/status.txt") & " 2>/dev/null; true"
				end try
				if st begins with "DONE" then exit repeat
			end repeat
		else
			error errMsg number errNum
		end if
	end try
	try
		set progress completed steps to archCount
	end try
	
	-- ---------- 6. summary ----------
	set summ to ""
	try
		set summ to do shell script "cat " & quoted form of (runWork & "/summary.txt") & " 2>/dev/null; true" as «class utf8»
	end try
	if summ is "" then
		set logTxt to ""
		try
			set logTxt to do shell script "tail -15 " & quoted form of (workDir & "/worker.log") & " 2>/dev/null; true"
		end try
		display dialog "The extraction helper ended without a summary." & return & return & logTxt & return & return & "Your original ZIP files were not modified. Anything already extracted is in:" & return & destPath buttons {"OK"} default button "OK" with icon stop with title dlgTitle
		return
	end if
	set reportPath to srcPath & "/" & reportName
	set reportOK to ((do shell script "test -f " & quoted form of reportPath & " && echo 1 || echo 0") is "1")
	if not reportOK then
		set reportPath to my kvGet(summ, "report")
		set reportOK to ((do shell script "test -f " & quoted form of reportPath & " && echo 1 || echo 0") is "1")
	end if
	set nIssues to 0
	try
		set nIssues to (my kvGet(summ, "issues")) as integer
	end try
	set msg to ""
	if wasCancelled then
		set msg to "CANCELLED - results are partial." & return & return
	else if nIssues is 0 then
		set msg to "Finished with no issues." & return & return
	else
		set msg to "Finished - " & nIssues & " issue(s) need your attention." & return & return
	end if
	set msg to msg & "Archives processed: " & my kvGet(summ, "archives") & "   (clean: " & my kvGet(summ, "ok") & ", with issues: " & my kvGet(summ, "issue_archives") & ", already done earlier: " & my kvGet(summ, "skipped_done") & ")" & return
	set msg to msg & "Files added to the output folder: " & my kvGet(summ, "merged") & return
	set msg to msg & "Identical duplicates skipped: " & my kvGet(summ, "dup_identical") & return
	set msg to msg & "Name conflicts (both copies kept): " & my kvGet(summ, "conflicts") & return
	set msg to msg & "Missing / corrupt files: " & my kvGet(summ, "bad_files") & return & return
	set msg to msg & "Output: " & destPath & return
	if reportOK then set msg to msg & "Report: " & reportPath & return
	set msg to msg & return & "Original ZIP files: untouched."
	try
		display notification "Extraction finished (" & nIssues & " issue(s))" with title dlgTitle
	end try
	set r to display dialog msg buttons {"Done", "Open Issue Report", "Open Output Folder"} default button "Open Output Folder" with title dlgTitle
	if button returned of r is "Open Output Folder" then
		do shell script "open " & quoted form of destPath
	else if button returned of r is "Open Issue Report" and reportOK then
		do shell script "open -t " & quoted form of reportPath
	end if
	my cleanupTemp(workDir)
end mainFlow

-- ---------------------------------------------------------------------
--  Decide what to process: selected ZIP files, a selected folder, or the
--  folder of the front Finder window.
-- ---------------------------------------------------------------------
on pickSource()
	set selItems to {}
	tell application "Finder"
		try
			set selItems to (selection as alias list)
		end try
	end tell
	set filePaths to {}
	set dirPaths to {}
	repeat with i from 1 to count of selItems
		set pth to POSIX path of (item i of selItems)
		if (do shell script "test -d " & quoted form of pth & " && echo 1 || echo 0") is "1" then
			set end of dirPaths to pth
		else
			set end of filePaths to pth
		end if
	end repeat
	if (count of filePaths) > 0 then
		set parentDir to do shell script "dirname " & quoted form of (item 1 of filePaths)
		repeat with p in filePaths
			if (do shell script "dirname " & quoted form of (contents of p)) is not parentDir then
				display dialog "Please select ZIP files from ONE folder only (or select the folder itself)." buttons {"OK"} default button "OK" with icon caution with title dlgTitle
				error number -128
			end if
		end repeat
		return {parentDir, filePaths}
	else if (count of dirPaths) is 1 then
		return {my stripSlash(item 1 of dirPaths), {}}
	else if (count of dirPaths) > 1 then
		display dialog "Several folders are selected. Select ONE folder (or the ZIP files), then run again." buttons {"OK"} default button "OK" with icon caution with title dlgTitle
		error number -128
	end if
	set frontPath to ""
	tell application "Finder"
		try
			set frontPath to POSIX path of ((target of front Finder window) as alias)
		end try
	end tell
	if frontPath is "" then
		set frontPath to POSIX path of (choose folder with prompt "Choose the folder that contains the downloaded ZIP files:")
	end if
	return {my stripSlash(frontPath), {}}
end pickSource

-- ---------------------------------------------------------------------
--  Small helpers
-- ---------------------------------------------------------------------
on afterBar(ln)
	if (count of ln) < 6 then return ""
	return text 6 thru -1 of ln
end afterBar

on stripSlash(p)
	return do shell script "p=" & quoted form of p & "; printf '%s' \"${p%/}\""
end stripSlash

on splitBy(txt, delim)
	set oldTID to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delim
	set parts to text items of txt
	set AppleScript's text item delimiters to oldTID
	return parts
end splitBy

on joinLines(lst, maxCount)
	set out to ""
	set n to count of lst
	repeat with i from 1 to n
		if i > maxCount then
			set out to out & "... and " & (n - maxCount) & " more (see the report)" & return
			exit repeat
		end if
		set out to out & "- " & (item i of lst) & return
	end repeat
	return out
end joinLines

on humanSize(nTxt)
	try
		return do shell script "awk -v b=" & nTxt & " 'BEGIN{ if (b>=1073741824) printf \"%.2f GB\", b/1073741824; else if (b>=1048576) printf \"%.1f MB\", b/1048576; else printf \"%d KB\", b/1024 }'"
	on error
		return nTxt & " bytes"
	end try
end humanSize

on kvGet(summ, k)
	repeat with ln in paragraphs of summ
		set ln to contents of ln
		if ln begins with (k & "=") then
			if (count of ln) > ((count of k) + 1) then return text ((count of k) + 2) thru -1 of ln
			return ""
		end if
	end repeat
	return "0"
end kvGet

on cleanupTemp(d)
	try
		if d begins with "/tmp/zipconsol." then do shell script "rm -rf " & quoted form of d
	end try
end cleanupTemp

-- ---------------------------------------------------------------------
--  The helper shell script (written to /tmp at run time)
-- ---------------------------------------------------------------------
on buildWorker()
	set w to ""
	set w to w & my workerPart1()
	set w to w & my workerPart2()
	set w to w & my workerPart3()
	set w to w & my workerPart4()
	set w to w & my workerPart5()
	return w
end buildWorker

on workerPart1()
	set t to ""
	set t to t & "#!/bin/bash" & linefeed
	set t to t & "# ZIP Extract & Consolidate worker (called by the AppleScript wrapper)" & linefeed
	set t to t & "# usage: worker.sh MODE SRC DEST LISTFILE WORK     (MODE = scan | run)" & linefeed
	set t to t & "MODE=\"$1\"; SRC=\"$2\"; DEST=\"$3\"; LISTFILE=\"$4\"; WORK=\"$5\"" & linefeed
	set t to t & "" & linefeed
	set t to t & "export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"" & linefeed
	set t to t & "# UTF-8 locale so Sinhala / Tamil / any non-ASCII file names are kept intact" & linefeed
	set t to t & "if locale -a 2>/dev/null | grep -qi '^en_US\\.utf-\\{0,1\\}8$'; then export LC_ALL=en_US.UTF-8" & linefeed
	set t to t & "elif locale -a 2>/dev/null | grep -qi '^c\\.utf-\\{0,1\\}8$'; then export LC_ALL=C.UTF-8; fi" & linefeed
	set t to t & "" & linefeed
	set t to t & "IS_MAC=0; [ \"$(uname -s)\" = \"Darwin\" ] && IS_MAC=1" & linefeed
	set t to t & "fsize()  { if [ $IS_MAC = 1 ]; then stat -f%z \"$1\" 2>/dev/null; else stat -c%s \"$1\" 2>/dev/null; fi; }" & linefeed
	set t to t & "fmtime() { if [ $IS_MAC = 1 ]; then stat -f%m \"$1\" 2>/dev/null; else stat -c%Y \"$1\" 2>/dev/null; fi; }" & linefeed
	set t to t & "lower()  { printf '%s' \"$1\" | tr 'A-Z' 'a-z'; }" & linefeed
	set t to t & "" & linefeed
	set t to t & "# ---------- tool detection ----------" & linefeed
	set t to t & "SZ=\"\"; SZ_VER=\"\"" & linefeed
	set t to t & "for c in 7zz 7zzs 7z; do" & linefeed
	set t to t & "  p=$(command -v \"$c\" 2>/dev/null)" & linefeed
	set t to t & "  if [ -n \"$p\" ]; then SZ=\"$p\"; break; fi" & linefeed
	set t to t & "done" & linefeed
	set t to t & "[ -n \"$SZ\" ] && SZ_VER=$(\"$SZ\" 2>&1 </dev/null | grep -m1 -i '7-zip' | tr -d '\\r')" & linefeed
	set t to t & "UNAR=$(command -v unar 2>/dev/null)" & linefeed
	set t to t & "DITTO=$(command -v ditto 2>/dev/null)" & linefeed
	set t to t & "UNZIP=$(command -v unzip 2>/dev/null)" & linefeed
	set t to t & "ZIPB=$(command -v zip 2>/dev/null)" & linefeed
	set t to t & "BSDTAR=\"\"; if tar --version 2>/dev/null | grep -qi bsdtar; then BSDTAR=$(command -v tar); fi" & linefeed
	set t to t & "BREW=$(command -v brew 2>/dev/null)" & linefeed
	set t to t & "" & linefeed
	set t to t & "mkdir -p \"$WORK\" 2>/dev/null" & linefeed
	set t to t & ": > \"$WORK/issues.tsv\"" & linefeed
	set t to t & "" & linefeed
	set t to t & "issue() { printf '%s\\t%s\\t%s\\n' \"$1\" \"$2\" \"$3\" >> \"$WORK/issues.tsv\"; }" & linefeed
	set t to t & "status() { printf 'STEP|%s|%s|%s\\n' \"$1\" \"$2\" \"$3\" > \"$WORK/status.tmp\"; mv -f \"$WORK/status.tmp\" \"$WORK/status.txt\"; }" & linefeed
	set t to t & "" & linefeed
	set t to t & "nearest_existing() { d=\"$1\"; while [ ! -d \"$d\" ] && [ \"$d\" != \"/\" ] && [ -n \"$d\" ]; do d=$(dirname \"$d\"); done; printf '%s' \"$d\"; }" & linefeed
	set t to t & "free_bytes() { df -Pk \"$(nearest_existing \"$1\")\" 2>/dev/null | awk 'NR==2{printf \"%.0f\", $4*1024}'; }" & linefeed
	set t to t & "" & linefeed
	set t to t & "has_ci() { [ -f \"$1/$2.$3\" ] || [ -f \"$1/$2.$(printf '%s' \"$3\" | tr 'a-z' 'A-Z')\" ]; }" & linefeed
	set t to t & "" & linefeed
	set t to t & "# ---------- discovery ----------" & linefeed
	set t to t & "discover() {" & linefeed
	set t to t & "  : > \"$WORK/plan.tsv\"; : > \"$WORK/warn.txt\"; : > \"$WORK/sigfiles.txt\"" & linefeed
	set t to t & "  if [ -n \"$LISTFILE\" ] && [ -s \"$LISTFILE\" ]; then cp \"$LISTFILE\" \"$WORK/cand_raw.txt\"" & linefeed
	set t to t & "  else find \"$SRC\" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | sort > \"$WORK/cand_raw.txt\"; fi" & linefeed
	set t to t & "  IGNORED=0" & linefeed
	set t to t & "  while IFS= read -r f; do" & linefeed
	set t to t & "    [ -f \"$f\" ] || continue" & linefeed
	set t to t & "    n=$(basename \"$f\"); d=$(dirname \"$f\"); lc=$(lower \"$n\"); echo \"$f\" >> \"$WORK/sigfiles.txt\"" & linefeed
	set t to t & "    case \"$lc\" in" & linefeed
	set t to t & "      *.zip)" & linefeed
	set t to t & "        base=\"${n%.*}\"" & linefeed
	set t to t & "        if has_ci \"$d\" \"$base\" z01; then" & linefeed
	set t to t & "          i=1; parts=0" & linefeed
	set t to t & "          while [ $i -le 99 ]; do" & linefeed
	set t to t & "            nn=$(printf '%02d' $i)" & linefeed
	set t to t & "            if has_ci \"$d\" \"$base\" \"z$nn\"; then parts=$i; i=$((i+1)); else break; fi" & linefeed
	set t to t & "          done" & linefeed
	set t to t & "          j=$((parts+1)); k=$((parts+3))" & linefeed
	set t to t & "          while [ $j -le $k ] && [ $j -le 99 ]; do" & linefeed
	set t to t & "            if has_ci \"$d\" \"$base\" \"z$(printf '%02d' $j)\"; then echo \"Split ZIP \\\"$base\\\": part z$(printf '%02d' $((parts+1))) is missing (z$(printf '%02d' $j) exists)\" >> \"$WORK/warn.txt\"; fi" & linefeed
	set t to t & "            j=$((j+1))" & linefeed
	set t to t & "          done" & linefeed
	set t to t & "          for ((q=1;q<=parts;q++)); do for e in z$(printf '%02d' $q) Z$(printf '%02d' $q); do [ -f \"$d/$base.$e\" ] && echo \"$d/$base.$e\" >> \"$WORK/sigfiles.txt\"; done; done" & linefeed
	set t to t & "          printf 'splitzip\\t%s\\t%s\\n' \"$f\" \"$((parts+1))\" >> \"$WORK/plan.tsv\"" & linefeed
	set t to t & "        else" & linefeed
	set t to t & "          printf 'zip\\t%s\\t1\\n' \"$f\" >> \"$WORK/plan.tsv\"" & linefeed
	set t to t & "        fi ;;" & linefeed
	set t to t & "      *.z[0-9][0-9])" & linefeed
	set t to t & "        base=\"${n%.*}\"; num=\"${lc##*.z}\"" & linefeed
	return t
end workerPart1

on workerPart2()
	set t to ""
	set t to t & "        if ! has_ci \"$d\" \"$base\" zip; then" & linefeed
	set t to t & "          echo \"Split ZIP \\\"$base\\\": part .z$num found but the final \\\"$base.zip\\\" is missing - cannot be extracted\" >> \"$WORK/warn.txt\"" & linefeed
	set t to t & "          issue PART_MISSING \"$n\" \"final .zip part missing\"" & linefeed
	set t to t & "        elif [ \"$num\" != \"01\" ] && ! has_ci \"$d\" \"$base\" z01; then" & linefeed
	set t to t & "          echo \"Split ZIP \\\"$base\\\": .z01 is missing\" >> \"$WORK/warn.txt\"" & linefeed
	set t to t & "        fi ;;" & linefeed
	set t to t & "      *.zip.[0-9][0-9][0-9]|*.7z.[0-9][0-9][0-9]|*.rar.[0-9][0-9][0-9]|*.tar.gz.[0-9][0-9][0-9]|*.tar.[0-9][0-9][0-9])" & linefeed
	set t to t & "        base=\"${n%.*}\"; num=\"${lc##*.}\"" & linefeed
	set t to t & "        if [ \"$num\" = \"001\" ]; then" & linefeed
	set t to t & "          i=1; parts=0" & linefeed
	set t to t & "          while [ $i -le 999 ]; do" & linefeed
	set t to t & "            nn=$(printf '%03d' $i)" & linefeed
	set t to t & "            if [ -f \"$d/$base.$nn\" ]; then parts=$i; echo \"$d/$base.$nn\" >> \"$WORK/sigfiles.txt\"; i=$((i+1)); else break; fi" & linefeed
	set t to t & "          done" & linefeed
	set t to t & "          if [ -f \"$d/$base.$(printf '%03d' $((parts+2)))\" ]; then echo \"Multipart \\\"$base\\\": part $(printf '%03d' $((parts+1))) is missing\" >> \"$WORK/warn.txt\"; issue PART_MISSING \"$n\" \"part $(printf '%03d' $((parts+1))) missing\"; fi" & linefeed
	set t to t & "          printf 'splitnum\\t%s\\t%s\\n' \"$f\" \"$parts\" >> \"$WORK/plan.tsv\"" & linefeed
	set t to t & "        elif [ ! -f \"$d/$base.001\" ]; then" & linefeed
	set t to t & "          echo \"Multipart \\\"$base\\\": .001 is missing ($n found)\" >> \"$WORK/warn.txt\"; issue PART_MISSING \"$n\" \".001 missing\"" & linefeed
	set t to t & "        fi ;;" & linefeed
	set t to t & "      *.part[0-9]*.rar)" & linefeed
	set t to t & "        pn=$(printf '%s' \"$lc\" | sed -E 's/.*\\.part0*([0-9]+)\\.rar$/\\1/')" & linefeed
	set t to t & "        if [ \"$pn\" = \"1\" ]; then printf 'other\\t%s\\t1\\n' \"$f\" >> \"$WORK/plan.tsv\"; fi ;;" & linefeed
	set t to t & "      *.7z|*.rar|*.tar|*.tgz|*.tar.gz|*.tar.bz2|*.tar.xz|*.tbz2|*.txz)" & linefeed
	set t to t & "        printf 'other\\t%s\\t1\\n' \"$f\" >> \"$WORK/plan.tsv\" ;;" & linefeed
	set t to t & "      *) IGNORED=$((IGNORED+1)) ;;" & linefeed
	set t to t & "    esac" & linefeed
	set t to t & "  done < \"$WORK/cand_raw.txt\"" & linefeed
	set t to t & "" & linefeed
	set t to t & "  # Google Drive numbered series (name-<stamp>-N-001.zip ...) : detect missing numbers" & linefeed
	set t to t & "  awk -F'\\t' '$1==\"zip\"||$1==\"splitzip\"{print $2}' \"$WORK/plan.tsv\" | while IFS= read -r p; do basename \"$p\"; done \\" & linefeed
	set t to t & "    | grep -E -- '-[0-9]{3}\\.[zZ][iI][pP]$' \\" & linefeed
	set t to t & "    | sed -E 's/^(.*)-([0-9]{3})\\.[zZ][iI][pP]$/\\1\\t\\2/' > \"$WORK/series.tsv\"" & linefeed
	set t to t & "  if [ -s \"$WORK/series.tsv\" ]; then" & linefeed
	set t to t & "    awk -F'\\t' '{k=$1; n=$2+0; cnt[k]++; if(n>mx[k])mx[k]=n; seen[k \",\" n]=1; keys[k]=1}" & linefeed
	set t to t & "      END{for(k in keys){ if(mx[k]>cnt[k]){ miss=\"\"; for(i=1;i<=mx[k];i++) if(!((k \",\" i) in seen)) miss=miss (miss==\"\"?\"\":\", \") sprintf(\"%03d\",i);" & linefeed
	set t to t & "        print \"Download series \\\"\" k \"\\\" is missing part(s): \" miss \" (found \" cnt[k] \", highest number \" sprintf(\"%03d\",mx[k]) \")\" }}}' \"$WORK/series.tsv\" >> \"$WORK/warn.txt\"" & linefeed
	set t to t & "    sed -n 's/^\\(Download series.*\\)$/\\1/p' \"$WORK/warn.txt\" | while IFS= read -r w; do issue PART_MISSING \"(zip series)\" \"$w\"; done" & linefeed
	set t to t & "  fi" & linefeed
	set t to t & "}" & linefeed
	set t to t & "" & linefeed
	set t to t & "# ---------- scan mode ----------" & linefeed
	set t to t & "if [ \"$MODE\" = \"scan\" ]; then" & linefeed
	set t to t & "  discover" & linefeed
	set t to t & "  echo \"SZ|$SZ|$SZ_VER\"" & linefeed
	set t to t & "  echo \"UNAR|$UNAR\"; echo \"BREW|$BREW\"" & linefeed
	set t to t & "  echo \"TAR|$BSDTAR\"; echo \"DITTO|$DITTO\"; echo \"UNZIP|$UNZIP\"; echo \"ZIP|$ZIPB\"" & linefeed
	set t to t & "  [ $IS_MAC = 1 ] && echo \"MACOS|$(sw_vers -productVersion 2>/dev/null)\"" & linefeed
	set t to t & "  comp=0" & linefeed
	set t to t & "  while IFS=$'\\t' read -r kind path parts; do" & linefeed
	set t to t & "    sz=$(fsize \"$path\"); [ -z \"$sz\" ] && sz=0" & linefeed
	set t to t & "    echo \"ARCH|$kind|$(basename \"$path\")|$parts|$sz\"" & linefeed
	set t to t & "    comp=$((comp+sz))" & linefeed
	set t to t & "  done < \"$WORK/plan.tsv\"" & linefeed
	set t to t & "  echo \"COMP|$comp\"; echo \"FREE|$(free_bytes \"$DEST\")\"; echo \"IGN|$IGNORED\"" & linefeed
	set t to t & "  while IFS= read -r w; do echo \"WARN|$w\"; done < \"$WORK/warn.txt\"" & linefeed
	set t to t & "  exit 0" & linefeed
	set t to t & "fi" & linefeed
	set t to t & "" & linefeed
	set t to t & "# ---------- run mode ----------" & linefeed
	set t to t & "REPORT_NAME=\"issue_files_name_with_path.txt\"" & linefeed
	set t to t & "N_ARCH=0; N_OK=0; N_ISSUE_ARCH=0; N_SKIPPED=0; N_MERGED=0; N_DUPSAME=0; N_CONFLICT=0; N_BADFILES=0" & linefeed
	set t to t & "FINISHED=0; CANCELLED=0; START_TS=$(date '+%Y-%m-%d %H:%M:%S')" & linefeed
	set t to t & "" & linefeed
	set t to t & "safe_rm() { case \"$1\" in \"$DEST\"/.extract_staging_*|\"$WORK\"/*) [ -e \"$1\" ] && rm -rf -- \"$1\" ;; esac; }" & linefeed
	set t to t & "" & linefeed
	set t to t & "finish() {" & linefeed
	set t to t & "  [ $FINISHED = 1 ] && return; FINISHED=1" & linefeed
	set t to t & "  for s in \"$DEST\"/.extract_staging_*; do [ -d \"$s\" ] && safe_rm \"$s\"; done" & linefeed
	set t to t & "  # source-archive integrity check (nothing may have changed)" & linefeed
	set t to t & "  if [ -s \"$WORK/sig_before.txt\" ]; then" & linefeed
	return t
end workerPart2

on workerPart3()
	set t to ""
	set t to t & "    : > \"$WORK/sig_after.txt\"" & linefeed
	set t to t & "    while IFS= read -r f; do printf '%s|%s|%s\\n' \"$f\" \"$(fsize \"$f\")\" \"$(fmtime \"$f\")\" >> \"$WORK/sig_after.txt\"; done < \"$WORK/sigfiles.txt\"" & linefeed
	set t to t & "    if ! cmp -s \"$WORK/sig_before.txt\" \"$WORK/sig_after.txt\"; then issue SOURCE_CHANGED \"(source archives)\" \"An original archive changed size/date during processing - please check\"; fi" & linefeed
	set t to t & "  fi" & linefeed
	set t to t & "  rdir=\"$SRC\"; [ -w \"$rdir\" ] || rdir=\"$DEST\"; [ -w \"$rdir\" ] || rdir=\"$HOME/Desktop\"" & linefeed
	set t to t & "  REPORT=\"$rdir/$REPORT_NAME\"" & linefeed
	set t to t & "  if [ -e \"$REPORT\" ]; then mv -f \"$REPORT\" \"$rdir/issue_files_name_with_path_$(date '+%Y%m%d-%H%M%S').txt\"; fi" & linefeed
	set t to t & "  {" & linefeed
	set t to t & "    echo \"ZIP EXTRACT & CONSOLIDATE - ISSUE REPORT\"" & linefeed
	set t to t & "    echo \"Started : $START_TS\"" & linefeed
	set t to t & "    echo \"Ended   : $(date '+%Y-%m-%d %H:%M:%S')\"" & linefeed
	set t to t & "    echo \"Source  : $SRC\"" & linefeed
	set t to t & "    echo \"Output  : $DEST\"" & linefeed
	set t to t & "    echo \"Tool    : ${SZ:-none (limited mode)} $SZ_VER\"" & linefeed
	set t to t & "    [ $CANCELLED = 1 ] && echo \"STATUS  : CANCELLED BY USER - results are partial\"" & linefeed
	set t to t & "    echo \"Original archives were NOT modified, moved or deleted.\"" & linefeed
	set t to t & "    echo" & linefeed
	set t to t & "    if [ ! -s \"$WORK/issues.tsv\" ]; then echo \"No issues found.\"; else" & linefeed
	set t to t & "      echo \"=== ARCHIVE-LEVEL ISSUES (type | archive | detail) ===\"" & linefeed
	set t to t & "      awk -F'\\t' '$1!=\"MISSING\"&&$1!=\"TRUNCATED_OR_CORRUPT\"&&$1!=\"CONFLICT_COPY\"{print \"[\" $1 \"] \" $2 \" | \" $3}' \"$WORK/issues.tsv\"" & linefeed
	set t to t & "      echo" & linefeed
	set t to t & "      echo \"=== FILE-LEVEL ISSUES (file path as inside the archive / Google Drive) ===\"" & linefeed
	set t to t & "      awk -F'\\t' '$1==\"MISSING\"||$1==\"TRUNCATED_OR_CORRUPT\"{print \"[\" $1 \"] \" $3 \"   (archive: \" $2 \")\"}' \"$WORK/issues.tsv\"" & linefeed
	set t to t & "      echo" & linefeed
	set t to t & "      echo \"=== NAME CONFLICTS (different file with same name; both kept, nothing overwritten) ===\"" & linefeed
	set t to t & "      awk -F'\\t' '$1==\"CONFLICT_COPY\"{print $3 \"   (archive: \" $2 \")\"}' \"$WORK/issues.tsv\"" & linefeed
	set t to t & "      echo" & linefeed
	set t to t & "      echo \"=== RE-DOWNLOAD LIST (one path per line) ===\"" & linefeed
	set t to t & "      awk -F'\\t' '$1==\"MISSING\"||$1==\"TRUNCATED_OR_CORRUPT\"{print $3}' \"$WORK/issues.tsv\" | sort -u" & linefeed
	set t to t & "    fi" & linefeed
	set t to t & "  } > \"$REPORT\" 2>/dev/null" & linefeed
	set t to t & "  {" & linefeed
	set t to t & "    echo \"archives=$N_ARCH\"; echo \"ok=$N_OK\"; echo \"issue_archives=$N_ISSUE_ARCH\"; echo \"skipped_done=$N_SKIPPED\"" & linefeed
	set t to t & "    echo \"merged=$N_MERGED\"; echo \"dup_identical=$N_DUPSAME\"; echo \"conflicts=$N_CONFLICT\"; echo \"bad_files=$N_BADFILES\"" & linefeed
	set t to t & "    echo \"issues=$(wc -l < \"$WORK/issues.tsv\" | tr -d ' ')\"; echo \"report=$REPORT\"; echo \"dest=$DEST\"; echo \"cancelled=$CANCELLED\"" & linefeed
	set t to t & "  } > \"$WORK/summary.txt\"" & linefeed
	set t to t & "  printf 'DONE|0|finished\\n' > \"$WORK/status.tmp\"; mv -f \"$WORK/status.tmp\" \"$WORK/status.txt\"" & linefeed
	set t to t & "}" & linefeed
	set t to t & "trap 'CANCELLED=1; exit 130' TERM INT HUP" & linefeed
	set t to t & "trap finish EXIT" & linefeed
	set t to t & "" & linefeed
	set t to t & "case \"$DEST\" in \"\"|\"/\") issue FATAL \"(destination)\" \"invalid destination\"; exit 2;; esac" & linefeed
	set t to t & "mkdir -p \"$DEST\" 2>/dev/null" & linefeed
	set t to t & "if [ ! -d \"$DEST\" ] || [ ! -w \"$DEST\" ]; then issue FATAL \"(destination)\" \"Destination not writable: $DEST\"; exit 2; fi" & linefeed
	set t to t & "for s in \"$DEST\"/.extract_staging_*; do [ -d \"$s\" ] && safe_rm \"$s\"; done   # leftovers of an interrupted run (temp copies only)" & linefeed
	set t to t & "" & linefeed
	set t to t & "discover" & linefeed
	set t to t & ": > \"$WORK/sig_before.txt\"" & linefeed
	set t to t & "while IFS= read -r f; do printf '%s|%s|%s\\n' \"$f\" \"$(fsize \"$f\")\" \"$(fmtime \"$f\")\" >> \"$WORK/sig_before.txt\"; done < \"$WORK/sigfiles.txt\"" & linefeed
	set t to t & "TOTAL=$(wc -l < \"$WORK/plan.tsv\" | tr -d ' ')" & linefeed
	set t to t & "MARKER=\"$DEST/.completed_archives.txt\"" & linefeed
	set t to t & "" & linefeed
	set t to t & "unique_target() {" & linefeed
	set t to t & "  t=\"$1\"; dir=$(dirname \"$t\"); b=$(basename \"$t\")" & linefeed
	set t to t & "  case \"$b\" in *.*) stem=\"${b%.*}\"; ext=\".${b##*.}\";; *) stem=\"$b\"; ext=\"\";; esac" & linefeed
	set t to t & "  i=1; while :; do c=\"$dir/$stem (conflict $i)$ext\"; [ -e \"$c\" ] || break; i=$((i+1)); done" & linefeed
	set t to t & "  printf '%s' \"$c\"" & linefeed
	set t to t & "}" & linefeed
	set t to t & "" & linefeed
	set t to t & "fallback_extract() {   # $1 archive  $2 staging ; returns 0 if something was extracted" & linefeed
	set t to t & "  a=\"$1\"; s=\"$2\"" & linefeed
	set t to t & "  for tool in unar bsdtar ditto unzip; do" & linefeed
	set t to t & "    case \"$tool\" in" & linefeed
	set t to t & "      unar)   [ -n \"$UNAR\" ]   && \"$UNAR\" -q -D -o \"$s\" \"$a\" </dev/null >> \"$WORK/fb.log\" 2>&1 ;;" & linefeed
	set t to t & "      bsdtar) [ -n \"$BSDTAR\" ] && \"$BSDTAR\" -xf \"$a\" -C \"$s\" </dev/null >> \"$WORK/fb.log\" 2>&1 ;;" & linefeed
	set t to t & "      ditto)  [ -n \"$DITTO\" ]  && \"$DITTO\" -x -k \"$a\" \"$s\" </dev/null >> \"$WORK/fb.log\" 2>&1 ;;" & linefeed
	set t to t & "      unzip)  [ -n \"$UNZIP\" ]  && \"$UNZIP\" -o -q \"$a\" -d \"$s\" </dev/null >> \"$WORK/fb.log\" 2>&1 ;;" & linefeed
	set t to t & "    esac" & linefeed
	set t to t & "    rc=$?" & linefeed
	set t to t & "    cnt=$(find \"$s\" -type f 2>/dev/null | head -1 | wc -l | tr -d ' ')" & linefeed
	return t
end workerPart3

on workerPart4()
	set t to ""
	set t to t & "    FB_TOOL=\"$tool\"; FB_RC=$rc" & linefeed
	set t to t & "    if [ \"$rc\" = \"0\" ] && [ \"$cnt\" != \"0\" ]; then return 0; fi" & linefeed
	set t to t & "    if [ \"$cnt\" != \"0\" ]; then return 0; fi   # partial result: caller flags it as unverified" & linefeed
	set t to t & "  done" & linefeed
	set t to t & "  return 1" & linefeed
	set t to t & "}" & linefeed
	set t to t & "" & linefeed
	set t to t & "process_archive() {  # kind path idx name" & linefeed
	set t to t & "  kind=\"$1\"; path=\"$2\"; idx=\"$3\"; name=\"$4\"" & linefeed
	set t to t & "  stg=\"$DEST/.extract_staging_$idx\"; safe_rm \"$stg\"; mkdir -p \"$stg\"" & linefeed
	set t to t & "  issues_before=$(wc -l < \"$WORK/issues.tsv\" | tr -d ' ')" & linefeed
	set t to t & "  asz=$(fsize \"$path\"); amt=$(fmtime \"$path\")" & linefeed
	set t to t & "  if [ -f \"$MARKER\" ] && grep -qxF -- \"$name|$asz|$amt\" \"$MARKER\"; then N_SKIPPED=$((N_SKIPPED+1)); safe_rm \"$stg\"; return; fi" & linefeed
	set t to t & "  UNVERIFIED=0; : > \"$WORK/expected.tsv\"; : > \"$WORK/badpaths.txt\"; ERRSUMMARY=\"\"" & linefeed
	set t to t & "  USE_PATH=\"$path\"; TMPCOMB=\"\"" & linefeed
	set t to t & "" & linefeed
	set t to t & "  if [ -n \"$SZ\" ]; then" & linefeed
	set t to t & "    \"$SZ\" l -slt \"$path\" </dev/null > \"$WORK/l.txt\" 2>&1" & linefeed
	set t to t & "    awk '/^----------$/{inent=1;next} !inent{next}" & linefeed
	set t to t & "         /^Path = /{flush(); p=substr($0,8); sz=\"\"; dir=0; next}" & linefeed
	set t to t & "         /^Folder = /{dir=($0==\"Folder = +\")}" & linefeed
	set t to t & "         /^Size = /{sz=substr($0,8)}" & linefeed
	set t to t & "         /^$/{flush()}" & linefeed
	set t to t & "         END{flush()}" & linefeed
	set t to t & "         function flush(){ if(p!=\"\" && !dir && sz!=\"\" && p !~ /(^|\\/)__MACOSX\\// && p !~ /(^|\\/)\\.DS_Store$/) print sz \"\\t\" p; p=\"\" }' \"$WORK/l.txt\" > \"$WORK/expected.tsv\"" & linefeed
	set t to t & "    if grep -q '^Encrypted = +' \"$WORK/l.txt\"; then" & linefeed
	set t to t & "      issue ARCHIVE_ENCRYPTED \"$name\" \"Password-protected archive - cannot extract automatically\"; safe_rm \"$stg\"; return" & linefeed
	set t to t & "    fi" & linefeed
	set t to t & "    if [ ! -s \"$WORK/expected.tsv\" ]; then" & linefeed
	set t to t & "      ERRSUMMARY=$(grep -E 'ERROR|Can not|Cannot|Unexpected|not archive|Headers|Wrong' \"$WORK/l.txt\" | head -2 | tr '\\n' ' ')" & linefeed
	set t to t & "      issue ARCHIVE_UNREADABLE \"$name\" \"7-Zip could not read the file list. ${ERRSUMMARY}\"" & linefeed
	set t to t & "      UNVERIFIED=1" & linefeed
	set t to t & "    else" & linefeed
	set t to t & "      need=$(awk -F'\\t' '{s+=$1} END{printf \"%.0f\", s*1.02+104857600}' \"$WORK/expected.tsv\"); free=$(free_bytes \"$DEST\")" & linefeed
	set t to t & "      if awk -v a=\"$free\" -v b=\"$need\" 'BEGIN{exit !(a+0<b+0)}'; then" & linefeed
	set t to t & "        issue ARCHIVE_NO_SPACE \"$name\" \"Not enough free disk space (need about $((need/1048576)) MB, free $((free/1048576)) MB). Free space and run again.\"" & linefeed
	set t to t & "        safe_rm \"$stg\"; return" & linefeed
	set t to t & "      fi" & linefeed
	set t to t & "      \"$SZ\" x -y -bd '-xr!__MACOSX' '-xr!.DS_Store' -o\"$stg\" \"$path\" </dev/null > \"$WORK/x.txt\" 2>&1" & linefeed
	set t to t & "      grep -E '^ERROR' \"$WORK/x.txt\" | sed -E 's/^ERROR: ([^:]*) : (.*)$/\\2/' | grep -v '^ERROR' > \"$WORK/badpaths.txt\"" & linefeed
	set t to t & "      ERRSUMMARY=$(grep -E '^ERROR' \"$WORK/x.txt\" | head -3 | tr '\\n' ' ')" & linefeed
	set t to t & "    fi" & linefeed
	set t to t & "  else" & linefeed
	set t to t & "    UNVERIFIED=1" & linefeed
	set t to t & "  fi" & linefeed
	set t to t & "" & linefeed
	set t to t & "  if [ \"$UNVERIFIED\" = \"1\" ]; then" & linefeed
	set t to t & "    # limited mode / unreadable listing: try the built-in extractors" & linefeed
	set t to t & "    case \"$kind\" in" & linefeed
	set t to t & "      splitzip) if [ -n \"$ZIPB\" ]; then TMPCOMB=\"$WORK/combined_$idx.zip\"; \"$ZIPB\" -q -s 0 \"$path\" --out \"$TMPCOMB\" </dev/null >/dev/null 2>&1 && USE_PATH=\"$TMPCOMB\"; fi ;;" & linefeed
	set t to t & "      splitnum) base=\"${path%.001}\"; TMPCOMB=\"$WORK/combined_$idx.bin\"; cat \"$base\".[0-9][0-9][0-9] > \"$TMPCOMB\" 2>/dev/null && USE_PATH=\"$TMPCOMB\" ;;" & linefeed
	set t to t & "    esac" & linefeed
	set t to t & "    : > \"$WORK/fb.log\"" & linefeed
	set t to t & "    if fallback_extract \"$USE_PATH\" \"$stg\"; then" & linefeed
	set t to t & "      if [ \"$FB_RC\" = \"0\" ] && [ \"$FB_TOOL\" != \"unzip\" ]; then" & linefeed
	set t to t & "        UNVERIFIED=0   # tool finished with exit 0 (it checks CRCs itself) and keeps Unicode names" & linefeed
	set t to t & "      else" & linefeed
	set t to t & "        issue ARCHIVE_UNVERIFIED \"$name\" \"Extracted with fallback tool ($FB_TOOL, exit $FB_RC) without per-file checking - files placed in _UNVERIFIED_FROM_ARCHIVES. Install 7-Zip (brew install sevenzip) and re-run.\"" & linefeed
	set t to t & "      fi" & linefeed
	set t to t & "    else" & linefeed
	set t to t & "      issue ARCHIVE_FAILED \"$name\" \"No extractor could read this archive (corrupt or incomplete download). $(head -2 \"$WORK/fb.log\" 2>/dev/null | tr '\\n' ' ')\"" & linefeed
	set t to t & "      safe_rm \"$stg\"; [ -n \"$TMPCOMB\" ] && rm -f \"$TMPCOMB\"; return" & linefeed
	set t to t & "    fi" & linefeed
	set t to t & "    [ -n \"$TMPCOMB\" ] && rm -f \"$TMPCOMB\"" & linefeed
	set t to t & "  else" & linefeed
	set t to t & "    # ---- verify every expected file: present, right size, no reported error ----" & linefeed
	set t to t & "    arch_bad=0" & linefeed
	set t to t & "    while IFS=$'\\t' read -r esz epath; do" & linefeed
	set t to t & "      f=\"$stg/$epath\"" & linefeed
	set t to t & "      if [ ! -f \"$f\" ]; then issue MISSING \"$name\" \"$epath\"; arch_bad=$((arch_bad+1)); continue; fi" & linefeed
	return t
end workerPart4

on workerPart5()
	set t to ""
	set t to t & "      if [ \"$(fsize \"$f\")\" != \"$esz\" ] || { [ -s \"$WORK/badpaths.txt\" ] && grep -qxF -- \"$epath\" \"$WORK/badpaths.txt\"; }; then" & linefeed
	set t to t & "        issue TRUNCATED_OR_CORRUPT \"$name\" \"$epath\"; rm -f -- \"$f\"; arch_bad=$((arch_bad+1))" & linefeed
	set t to t & "      fi" & linefeed
	set t to t & "    done < \"$WORK/expected.tsv\"" & linefeed
	set t to t & "    N_BADFILES=$((N_BADFILES+arch_bad))" & linefeed
	set t to t & "    if [ $arch_bad -eq 0 ] && [ -n \"$ERRSUMMARY\" ]; then issue ARCHIVE_ERRORS \"$name\" \"$ERRSUMMARY\"; fi" & linefeed
	set t to t & "  fi" & linefeed
	set t to t & "" & linefeed
	set t to t & "  # ---- merge staging -> destination (never overwrite) ----" & linefeed
	set t to t & "  MB=\"$DEST\"" & linefeed
	set t to t & "  if [ \"$UNVERIFIED\" = \"1\" ]; then MB=\"$DEST/_UNVERIFIED_FROM_ARCHIVES/$name\"; mkdir -p \"$MB\"; fi" & linefeed
	set t to t & "  find \"$stg\" -mindepth 1 -type d > \"$WORK/stgdirs.txt\" 2>/dev/null" & linefeed
	set t to t & "  while IFS= read -r dd; do mkdir -p \"$MB/${dd#\"$stg\"/}\"; done < \"$WORK/stgdirs.txt\"" & linefeed
	set t to t & "  find \"$stg\" -type f > \"$WORK/stgfiles.txt\" 2>/dev/null" & linefeed
	set t to t & "  while IFS= read -r f; do" & linefeed
	set t to t & "    rel=\"${f#\"$stg\"/}\"; target=\"$MB/$rel\"; mkdir -p \"$(dirname \"$target\")\"" & linefeed
	set t to t & "    if [ ! -e \"$target\" ]; then" & linefeed
	set t to t & "      if mv -- \"$f\" \"$target\"; then N_MERGED=$((N_MERGED+1)); else issue MERGE_FAILED \"$name\" \"$rel\"; fi" & linefeed
	set t to t & "    elif [ -f \"$target\" ] && cmp -s -- \"$f\" \"$target\"; then" & linefeed
	set t to t & "      N_DUPSAME=$((N_DUPSAME+1)); rm -f -- \"$f\"" & linefeed
	set t to t & "    else" & linefeed
	set t to t & "      alt=$(unique_target \"$target\")" & linefeed
	set t to t & "      if mv -- \"$f\" \"$alt\"; then N_MERGED=$((N_MERGED+1)); N_CONFLICT=$((N_CONFLICT+1)); issue CONFLICT_COPY \"$name\" \"${alt#\"$DEST\"/}\"; else issue MERGE_FAILED \"$name\" \"$rel\"; fi" & linefeed
	set t to t & "    fi" & linefeed
	set t to t & "  done < \"$WORK/stgfiles.txt\"" & linefeed
	set t to t & "  safe_rm \"$stg\"" & linefeed
	set t to t & "" & linefeed
	set t to t & "  issues_after=$(wc -l < \"$WORK/issues.tsv\" | tr -d ' ')" & linefeed
	set t to t & "  if [ \"$issues_after\" = \"$issues_before\" ] && [ \"$UNVERIFIED\" = \"0\" ]; then" & linefeed
	set t to t & "    N_OK=$((N_OK+1)); echo \"$name|$asz|$amt\" >> \"$MARKER\"" & linefeed
	set t to t & "  else" & linefeed
	set t to t & "    N_ISSUE_ARCH=$((N_ISSUE_ARCH+1))" & linefeed
	set t to t & "  fi" & linefeed
	set t to t & "}" & linefeed
	set t to t & "" & linefeed
	set t to t & "if [ \"$TOTAL\" = \"0\" ]; then issue NO_ARCHIVES \"(none)\" \"No ZIP / split / multipart archives found in $SRC\"; exit 0; fi" & linefeed
	set t to t & "" & linefeed
	set t to t & "idx=0" & linefeed
	set t to t & "while IFS=$'\\t' read -r -u 3 kind path parts; do" & linefeed
	set t to t & "  idx=$((idx+1)); N_ARCH=$((N_ARCH+1)); name=$(basename \"$path\")" & linefeed
	set t to t & "  status \"$idx\" \"$TOTAL\" \"$name\"" & linefeed
	set t to t & "  process_archive \"$kind\" \"$path\" \"$idx\" \"$name\"" & linefeed
	set t to t & "done 3< \"$WORK/plan.tsv\"" & linefeed
	set t to t & "exit 0" & linefeed
	return t
end workerPart5

