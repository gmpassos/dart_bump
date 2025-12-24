- `bin/dart_bump.dart`:
  - Added `--diff-context` CLI option to specify number of context lines for `git diff` (default 10).
  - Improved parsing of `--extra-file` option to handle empty values gracefully.
  - Passed clamped `gitDiffLinesContext` (2 to 100) to `DartBump` constructor.

## 1.0.0

- Initial version.

- args_simple: ^1.1.0
