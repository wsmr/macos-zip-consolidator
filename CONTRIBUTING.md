# Contributing

Thanks for helping! The most valuable contribution right now is **testing on real Macs** (Intel / Apple silicon, different macOS versions) and sharing results.

## Layout
- `src/worker.sh` - the shell engine (all extraction / verification / merge logic).
- `src/wrapper.applescript.tpl` - the AppleScript UI (dialogs, Finder integration, progress).
- `build/build.py` - embeds the engine into the wrapper -> `dist/Extract_Consolidate_ZIPs.scpt`.
- `tests/run_tests.sh` - self-test (needs `zip` and `7zz` or `7z`).

## Workflow
1. Edit files in `src/` only - **never edit `dist/` by hand**.
2. `python3 build/build.py` to regenerate the `.scpt`.
3. `bash tests/run_tests.sh` must pass.
4. Commit both `src/` and the regenerated `dist/` file.

## Rules for the shell engine
- Must run on macOS's stock **bash 3.2** and BSD tools (no associative arrays, `mapfile`, GNU-only flags).
- Never write to, move, rename or delete a user's original archive.
- Never overwrite an existing file in the output folder.
- Report every problem in the issue report; never fail silently.

## Bug reports
Please attach `issue_files_name_with_path.txt` (remove private paths if needed), your macOS version, chip, and `7zz` version.
