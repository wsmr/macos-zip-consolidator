# Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "7-Zip (7zz) was not found" | Run `brew install sevenzip`, then run the script again (or continue in limited mode). |
| Script does nothing in FastScripts | The `.scpt` must be compiled once: open in Script Editor -> Compile -> Save as *Script*, or use `osacompile`. |
| macOS asks for permissions | Allow *Finder automation* and *Files & Folders* access for FastScripts / Script Editor. |
| "No archives were found" | Select the folder (or the ZIP files) in Finder first. Only the top level of the folder is scanned, not sub-folders. |
| `[PART_MISSING] ... missing part(s)` | A ZIP in the numbered series was never downloaded. Download it again from Google Drive. |
| `[TRUNCATED_OR_CORRUPT]` / `[MISSING]` | That ZIP was cut short or corrupted. Re-download the listed files (see RE-DOWNLOAD LIST) and run again. |
| `[ARCHIVE_UNREADABLE]` / `[ARCHIVE_FAILED]` | The ZIP is too damaged to read. Re-download that ZIP part. |
| `[ARCHIVE_NO_SPACE]` | Free disk space (about the unpacked size) and run again; finished archives are skipped. |
| `[ARCHIVE_ENCRYPTED]` | Password-protected - extract manually. |
| `[CONFLICT_COPY]` | Two different files had the same name; both were kept (`name (conflict 1).ext`). Compare and delete one. |
| Files in `_UNVERIFIED_FROM_ARCHIVES` | Limited mode could not verify them. Install 7-Zip and run again. |
| Want to re-extract an archive that was already done | Delete the hidden file `Consolidated_Extracted/.completed_archives.txt`. |
| Cancelled midway | Safe: staging is cleaned and the report is written. Run again to continue. |

## Reporting a bug

Open an issue with: macOS version, chip (Intel/Apple silicon), `7zz | head -2` output, and the contents of `issue_files_name_with_path.txt`.
