## 1.0.3

- Added `dryRun` mode to `DartBump`:
  - `dryRun` flag disables all file writes while performing full computations and Git operations.
  - When enabled, version bumps and changelog generation are previewed without modifying files.
  - Logs indicate skipped file writes for `pubspec.yaml`, `CHANGELOG.md`, and extra files.

- `DartBump`:
  - Added static `VERSION` field.
  - Added `dryRun` constructor parameter and field.
  - `bumpPatchVersion`: skips writing `pubspec.yaml` if `dryRun` is true.
  - `updateChangelog`: skips writing `CHANGELOG.md` if `dryRun` is true.
  - `updateExtraFiles`: skips writing extra files if `dryRun` is true.
  - `bump`: logs dry run mode and adjusts logging for skipped writes.

- CLI (`bin/dart_bump.dart`):
  - Added `-n, --dry-run` option to preview changes without modifying files.

- Shell script `bump.sh`:
  - Updated example to use `dart run bin/dart_bump.dart` instead of global activate.

## 1.0.2

- `dart_bump.dart`:
  - Added `--diff-tag` CLI option to specify a Git tag for generating diffs.

- `DartBump`:
  - Added `gitDiffTag` field to specify the Git tag reference for diffs.
  - Updated `extractGitPatch` to generate diffs from `gitDiffTag` to HEAD if provided.
  - Added support for special `gitDiffTag` values `last` or `latest` to automatically resolve the highest version Git tag.
  - Added `getGitTags` method to retrieve all Git tags sorted by version descending.
  - Added `getGitLastTag` method to return the highest Git tag or null if none exist.

## 1.0.1

- `bin/dart_bump.dart`:
  - Added `--diff-context` CLI option to specify number of context lines for `git diff` (default 10).
  - Improved parsing of `--extra-file` option to handle empty values gracefully.
  - Passed clamped `gitDiffLinesContext` (2 to 100) to `DartBump` constructor.

- `DartBump`:
  - Added `gitDiffLinesContext` field to control context lines in `git diff` (default 10).
  - Modified `extractGitPatch` to include `-U<gitDiffLinesContext>` argument in `git diff` command.

## 1.0.0

- Initial version.

- args_simple: ^1.1.0
