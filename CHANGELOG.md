# Changelog

All notable changes are documented here. Format: [Keep a Changelog](https://keepachangelog.com/), versioning: [SemVer](https://semver.org/).

## [1.0.0] - 2026-11-18
### Added
- Initial public release.
- Extracts plain, split (`.z01`), numbered (`.zip.001`) ZIPs and `.7z` / `.rar` / `.tar.*` archives into one consolidated folder.
- Google Drive support: independent `-001…-00N` parts, gap detection in the numbering, Unicode (Sinhala/Tamil/...) file names, incomplete-download detection.
- Per-file verification (size + CRC) with 7-Zip; damaged files never enter the output folder.
- Never overwrites: identical duplicates skipped, different files kept as `name (conflict N).ext`.
- Original archives are read-only; integrity (size/date) is re-checked after the run.
- `issue_files_name_with_path.txt` report with a ready-to-use re-download list.
- Limited mode using built-in macOS tools when 7-Zip is not installed.
- FastScripts-friendly flow (Finder selection / folder / front window), progress window, safe cancel.
- `tests/run_tests.sh` self-test and a build script that embeds the shell engine into the `.scpt`.
