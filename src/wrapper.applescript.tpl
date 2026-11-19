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
@@CALLS@@
	return w
end buildWorker

@@CHUNKS@@
