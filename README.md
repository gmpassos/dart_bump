# dart_bump

[![pub package](https://img.shields.io/pub/v/dart_bump.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/dart_bump)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/dart_bump?logo=git&logoColor=white)](https://github.com/gmpassos/dart_bump/releases)
[![Last Commit](https://img.shields.io/github/last-commit/gmpassos/dart_bump?logo=github&logoColor=white)](https://github.com/gmpassos/dart_bump/commits/main)
[![License](https://img.shields.io/github/license/gmpassos/dart_bump?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/dart_bump/blob/main/LICENSE)

`dart_bump` is a Dart automation tool for **safe, consistent version bump** in Dart projects.

It integrates with Git and OpenAI to:

* Extract the current Git diff automatically
* Generate structured and AI-assisted `CHANGELOG.md` entries
* Increment the version in `pubspec.yaml` (patch, minor, or major)
* Update version constants in source code and extra files
* Maintain consistent, low-effort releases across the project and the development team

Ideal for **automation, CI pipelines, and developer workflows**, `dart_bump` **simplifies and standardizes versioning**
while maintaining reliability.

---
Here’s a grammatically polished version:

## Features

* ⚡ Flexible usage via CLI (`dart_bump`) or programmatically through the `DartBump` class
* 🔢 Automatic semantic version bump (`pubspec.yaml`)
  * Defaults to patch, with optional minor or major increments
* 📝 AI-generated, structured CHANGELOG entries
  * Generated from the Git diff using your OpenAI API key (`--api-key`)
  * 🧩 Automatic Git diff extraction
      * From the working tree, a specific Git tag, or the last project tag
* 🔧 Automatic version synchronization in project files
  * Source code constants, and extra files configurable via `--extra-file`
* 🧪 Dry-run mode for safe previews without modifying files (`--dry-run`)
* ♻️ Fully overridable and testable logging

---

## Usage

### CLI

Activate the `dart_bump` command:

```bash
dart pub global activate dart_bump
```

Run `dart_bump` to automatically bump the patch version, update `CHANGELOG.md`, and synchronize API constants:

```bash
dart_bump [<project-dir>] [--api-key <key>] [--extra-file <file=regexp>]
```

**Options:**

* `<project-dir>`: Path to the Dart project 📁  (default: current directory)
* `--api-key <key>`: OpenAI API key 🔑  (optional; defaults to `OPENAI_API_KEY` environment variable)
* `--extra-file <file=regexp>`: Specify extra files to update with a Dart RegExp 🗂️ (multiple allowed)
* `--diff-tag <tag>`: Generate diff from the given Git tag to HEAD 🏷  (accepts tag `last`)
* `--diff-context <n>`: Number of context lines for git diff 📄  (default: 10)
* `--major`: Bump major version (breaking changes) 🧱
* `--minor`: Bump minor version (new features) 🧩
* `--patch`: Bump patch version (bug fixes) 🩹  (default)
* `--no-bump`: Skip version bumping entirely ⏭️
* `--no-changelog`: Skip CHANGELOG generation 📝
* `--no-extra`: Skip updating extra files 🗂️
* `-n, --dry-run`: Preview changes only — no files will be modified 🧪  (default: false)
* `-h, --help`: Show help message ❓

**Example usage:**

```bash
# Bump the current project using the OpenAI API key from environment
dart_bump

# Bump a project in another directory
dart_bump /path/to/project

# Bump version using an explicit OpenAI API key for CHANGELOG generation
dart_bump --api-key YOUR_API_KEY

# Bump a project in another directory, update an extra file,
# and provide an API key to generate a CHANGELOG entry:
dart_bump /path/to/backend-dir \
  --extra-file "lib/src/api.dart=version\\s*=\\s*'([^']+)'\\s*;" \
  --api-key sk-xyzkey

# Skip version bump, but generate the CHANGELOG
dart_bump --no-bump --api-key sk-xyzkey

# Bump version, but do NOT generate the CHANGELOG
dart_bump --no-changelog

# Bump version and generate the CHANGELOG, but skip extra file updates
dart_bump \
  --extra-file "lib/src/api.dart=version\\s*=\\s*'([^']+)'\\s*;" \
  --api-key sk-xyzkey \
  --no-extra
```
- ***The dart_bump CLI can be customized with one or more `--extra-file` entries,
allowing different projects to update additional files with the new version automatically.***

---

### Programmatic

You can use `dart_bump` directly in your Dart code by creating an instance of the `DartBump` class.
This allows full control over version bumping, CHANGELOG generation, and updating extra files, all without invoking the **CLI**.

```dart
import 'dart:io';
import 'package:dart_bump/dart_bump.dart';

void main() async {
  final bump = DartBump(
    Directory.current,
    changeLogGenerator: OpenAIChangeLogGenerator(
      apiKey: Platform.environment['OPENAI_API_KEY'],
    ),
  );

  final result = await bump.bump();

  if (result == null) {
    print('ℹ️  Nothing to bump — version is already up to date.');
    return;
  }

  print('🎯 New version: ${result.version}');

  final changelog = result.changeLogEntry;
  if (changelog != null && changelog.isNotEmpty) {
    print('📝 Generated CHANGELOG entry:');
    print('───────────────────────────────');
    print(changelog);
    print('───────────────────────────────');
  }
}
````

---

## Project-Standard Version Bumping with `./bump.sh`

The `dart_bump` package itself uses a committed `bump.sh` script.
It’s recommended to do the same in your projects.

By adding `bump.sh` to the project root **and committing it**, all developers bump versions in **exactly the same way**, with the same options, files, and rules.

**Example `bump.sh` (used by `dart_bump` itself):**

```bash
#!/bin/bash

API_KEY=$1

dart_bump . \
  --extra-file "lib/src/dart_bump_base.dart=static\\s+final\\s+String\\s+VERSION\\s*=\\s*['\"]([\\w.\\-]+)['\"]" \
  --api-key "$API_KEY"
```

**Usage:**

```bash
chmod +x bump.sh
./bump.sh sk-your-openai-api-key
```

Committing this script prevents configuration drift, enforces consistent versioning, and documents project-specific bump rules in a reproducible way.

---

## How It Works

1. Verifies the project is a Git repository ✔️
2. Runs `git diff` to extract changes 🧩
3. Sends the patch to ChatGPT to generate a CHANGELOG entry 🧠
4. Increments the patch version in `pubspec.yaml` 🔢
5. Prepends the entry to `CHANGELOG.md` 📝
6. Updates extra files (if present) 📄

All steps fail fast and log clearly.

---

## Requirements

* Git installed and available in PATH
* Dart 3.x+
* OpenAI API key (optional but recommended)

If no API key is provided, version bumping still works, but the CHANGELOG entry will be a placeholder.

---

## Logging

All output goes through:

```dart
void log(String message)
```

Override it to:

* Integrate with your logger
* Silence output
* Redirect logs to CI systems

---

## Issues & Feature Requests

Please report issues and request features via the
[issue tracker][tracker].

[tracker]: https://github.com/gmpassos/dart_bump/issues

---

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

---

## License

Dart free & open-source [license](https://github.com/dart-lang/stagehand/blob/master/LICENSE).
