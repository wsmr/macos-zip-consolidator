# macOS ZIP Consolidator

**Safely extract Google Drive ZIP downloads (and other ZIPs) into ONE organized folder on macOS - without ever touching your original archives.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey)
![Made with: AppleScript + Bash](https://img.shields.io/badge/made%20with-AppleScript%20%2B%20Bash-orange)

An AppleScript (`.scpt`) for **[FastScripts](https://red-sweater.com/fastscripts/)** (also runs from Script Editor) that detects, extracts, verifies and merges ZIP archives into a single folder, and tells you **exactly which files are damaged or missing** so you only re-download those.

### Repo Tree
macos-zip-consolidator/
├── README.md                 full docs: problem, features, install, usage, limits
├── LICENSE                   MIT (c) 2026 wsmr
├── CHANGELOG.md              v1.0.0 release notes
├── CONTRIBUTING.md           workflow and rules for contributors
├── .gitignore
├── dist/Extract_Consolidate_ZIPs.scpt    the script users download
├── src/worker.sh                         shell engine (the real logic)
├── src/wrapper.applescript.tpl           AppleScript UI (dialogs, Finder, progress)
├── build/build.py                        embeds the engine into the .scpt
├── tests/run_tests.sh                    13 self-tests (all pass here)
├── docs/TROUBLESHOOTING.md               symptom -> fix table
└── .github/                              bug and feature issue templates, CI workflow

---

## The problem it solves

When you download a large folder from Google Drive, it is delivered as several independent ZIPs:

```
My Folder-20260930T025711Z-1-001.zip
My Folder-20260930T025711Z-1-002.zip
...
```

On macOS this often goes wrong:

- Archive Utility creates a separate folder for every ZIP instead of one tree.
- `unzip`/`ditto`/`tar` stop at the first damaged file and report misleading errors (e.g. *"disk full?"*, *"Illegal byte sequence"*, *"Couldn't read pkzip signature"*).
- File names in Sinhala, Tamil, Chinese, etc. come out as `?????`.
- A part that was cut short during download silently leaves files missing or truncated, and you never learn which ones.

This tool handles all of that in one click.

## Features

- **Universal archive support** - plain `.zip`, split `.zip` + `.z01 .z02…`, numbered `.zip.001 .002…`, plus `.7z`, `.rar`, `.tar.gz`.
- **Google Drive aware** - merges `-001 … -00N` parts into one tree and warns when a number in the series is missing.
- **Verifies every file** (size + CRC) and keeps damaged files **out** of your consolidated folder.
- **One consolidated folder** - everything merged into a single tree, empty folders included.
- **Never overwrites** - identical duplicates are skipped; different files with the same name are kept as `name (conflict 1).ext`.
- **Originals are read-only** - never modified, moved, renamed or deleted; their size/date is re-checked after the run.
- **Issue report** - `issue_files_name_with_path.txt` next to your ZIPs, with a copy-paste **re-download list** of Google Drive paths.
- **Unicode-safe** file names (tested with Sinhala).
- **Resumable & safe to cancel** - re-run any time; finished archives are skipped; cancel leaves no half-extracted clutter.
- **Clear errors** - missing parts, encrypted archives, corrupt/incomplete downloads, no disk space, merge failures.
- **FastScripts friendly** - works from the Finder selection, a selected folder, or the front Finder window; progress window included.

## Requirements

| | |
|---|---|
| macOS | 10.13 or newer (Intel and Apple silicon) |
| Recommended | [7-Zip](https://www.7-zip.org/) CLI via Homebrew: `brew install sevenzip` |
| Optional | FastScripts (any launcher/Script Editor works) |

**7-Zip is strongly recommended.** It is the only common tool that skips damaged entries instead of aborting, verifies each file and reads split ZIPs reliably. Without it the script runs in *limited mode* using the built-in macOS tools (`ditto`, `bsdtar`, `unzip`, and `unar` if installed): anything it cannot verify is placed in a separate `_UNVERIFIED_FROM_ARCHIVES` folder.

No Homebrew? Install it from <https://brew.sh>, or download the macOS command-line 7-Zip (`7zz`) from <https://www.7-zip.org> and copy it to `/usr/local/bin`.

## Installation

1. Download `dist/Extract_Consolidate_ZIPs.scpt` (or clone this repo).
2. Compile it once (the file is AppleScript source text):
   - **Script Editor:** open it -> *Compile* -> *File > Save...* -> format **Script**; **or**
   - **Terminal:** `osacompile -o ~/Library/Scripts/Extract_Consolidate_ZIPs.scpt dist/Extract_Consolidate_ZIPs.scpt`
3. Place it in `~/Library/Scripts/` so FastScripts lists it (optionally assign a hotkey).
4. First run: allow the macOS prompts (Finder automation, access to Downloads/Documents).

## Usage

1. In Finder open the folder containing your downloaded ZIPs - **or** select that folder - **or** select only the ZIP files you want to process.
2. Run **Extract_Consolidate_ZIPs** from FastScripts.
3. Review the confirmation (archive count, free space, warnings, output folder - changeable) and click **Start**.
4. When it finishes, use **Open Output Folder** / **Open Issue Report**.

Default output: `<your ZIP folder>/Consolidated_Extracted/`

```
Consolidated_Extracted/
└── My Folder/                      <- the top-level folder from Google Drive
    ├── 01. Physics/ ...
    ├── 02. Chemistry/ ...
    └── ...
```

### Fixing a damaged download

Open `issue_files_name_with_path.txt`, scroll to **RE-DOWNLOAD LIST**, download just those items (or their parent folders) from Google Drive, drop the new ZIP(s) into the same folder and run the script again. Already-complete archives are skipped, and the new files are merged into the same tree.

## Example report

```
ZIP EXTRACT & CONSOLIDATE - ISSUE REPORT
Source  : /Users/me/Downloads/ZIP
Output  : /Users/me/Downloads/ZIP/Consolidated_Extracted
Original archives were NOT modified, moved or deleted.

=== ARCHIVE-LEVEL ISSUES (type | archive | detail) ===
[PART_MISSING] (zip series) | Download series "Drive-2026...-1" is missing part(s): 003 (found 4, highest number 005)
[ARCHIVE_UNREADABLE] Trunc.zip | 7-Zip could not read the file list. ...

=== FILE-LEVEL ISSUES (file path as inside the archive / Google Drive) ===
[TRUNCATED_OR_CORRUPT] Drive Folder/01 Physics/Sub/f6.bin   (archive: Drive-...-1-005.zip)

=== RE-DOWNLOAD LIST (one path per line) ===
Drive Folder/01 Physics/Sub/f6.bin
```

## Safety guarantees

1. Original archives are opened read-only; nothing is ever written to, moved or deleted from them.
2. Extraction happens in a hidden staging folder; only verified files are moved into the output folder.
3. Existing files are never overwritten.
4. Disk space is checked before each archive.
5. Temporary files are removed on exit, error or cancel.

## Limitations

- It cannot recover data Google Drive never delivered - it only finds exactly what is missing.
- If the **last** ZIP of a series is missing it cannot be detected (Drive does not record the total). Gaps in the *middle* are detected. Compare with the item count in Drive.
- Password-protected archives are reported, not extracted. ZIPs nested inside ZIPs are left as extracted.
- Limited mode (no 7-Zip) has weaker per-file verification and Unicode/split handling.
- The progress window may look different (or not appear) depending on the launcher.

## How it works

```
Finder selection / folder -> scan (read-only) -> pre-flight dialog
   -> for each archive: list -> disk-space check -> extract to staging
   -> verify every file (size + CRC) -> merge into one tree (no overwrite)
   -> report + summary
```

The AppleScript wrapper (`src/wrapper.applescript.tpl`) handles dialogs and Finder; the shell engine (`src/worker.sh`) does the work. `build/build.py` embeds the engine into one self-contained `.scpt`.

## Development

```bash
python3 build/build.py     # regenerate dist/Extract_Consolidate_ZIPs.scpt from src/
bash tests/run_tests.sh    # self-test (needs zip + 7zz or 7z)
```

CI runs the self-test on Ubuntu and macOS and compiles the AppleScript with `osacompile`. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Status

- Shell engine: self-tests pass on Linux with 7-Zip 23.01 (plain/Drive-style/split/numbered/corrupt/truncated/encrypted/Unicode/conflict cases).
- AppleScript wrapper on macOS: please report your results (macOS version, chip) in an issue - see [Troubleshooting](docs/TROUBLESHOOTING.md).

## Credits

[7-Zip](https://www.7-zip.org/) (Igor Pavlov), [Homebrew](https://brew.sh), [FastScripts](https://red-sweater.com/fastscripts/) by Red Sweater Software.

## License

[MIT](LICENSE) (c) 2026 wsmr
