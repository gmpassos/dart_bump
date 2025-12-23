# dart_bump

[![pub package](https://img.shields.io/pub/v/dart_bump.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/dart_bump)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/dart_bump?logo=git&logoColor=white)](https://github.com/gmpassos/dart_bump/releases)
[![Last Commit](https://img.shields.io/github/last-commit/gmpassos/dart_bump?logo=github&logoColor=white)](https://github.com/gmpassos/dart_bump/commits/main)
[![License](https://img.shields.io/github/license/gmpassos/dart_bump?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/dart_bump/blob/main/LICENSE)

`dart_bump` is a Dart automation tool for **safe, consistent patch version bumps** in Dart projects.

It integrates with Git and OpenAI to:
- Extract the current Git diff
- Generate a structured `CHANGELOG.md` entry
- Increment the patch version in `pubspec.yaml`
- Update API version constants
- Keep releases consistent and low-effort

Designed for **automation, CI usage, and developer tooling**.

---

## Features

- 🔢 Automatic patch version bump (`x.y.z → x.y.(z+1)`)
- 🧩 Git diff extraction
- 📝 AI-generated, structured CHANGELOG entries
- 🔧 API version synchronization
- ♻️ Fully overridable logging

---

## Usage

### Programmatic

```dart
import 'dart:io';
import 'package:dart_bump/dart_bump.dart';

void main() async {
  final bump = DartBump(
    Directory.current,
    Platform.environment['OPENAI_API_KEY'],
    DartBump.defaultChangelogPrompt,
  );

  final result = await bump.bump();

  print('New version: ${result?.version}');
}
````

## CLI

Activate the `dart_bump` command:

```bash
dart pub global activate dart_bump
````

### dart_bump

Run `dart_bump` to automatically bump the patch version, update `CHANGELOG.md`, and synchronize API constants.

```bash
dart_bump [--project-dir <path>] [--api-key <key>]
```

Options:

* `--project-dir <path>`: Path to the Dart project (default: current directory)
* `--api-key <key>`: OpenAI API key (optional; defaults to `OPENAI_API_KEY` environment variable)
* `-h, --help`: Show help message

Example usage:

```bash
# Bump current project with OpenAI API key from env
dart_bump

# Bump a project in another directory
dart_bump --project-dir /path/to/project

# Bump with an explicit OpenAI API key
dart_bump --api-key YOUR_API_KEY
```

---

## How It Works

1. Verifies the project is a Git repository
2. Runs `git diff` to extract changes
3. Sends the patch to ChatGPT to generate a CHANGELOG entry
4. Increments the patch version in `pubspec.yaml`
5. Prepends the entry to `CHANGELOG.md`
6. Updates `lib/src/api_root.dart` (if present)

All steps fail fast and log clearly.

---

## Requirements

* Git installed and available in PATH
* Dart 3.x+
* OpenAI API key (optional but recommended)

If no API key is provided, version bumping still works, but the changelog entry will be a placeholder.

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

## Features and Bugs

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
