import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Automates semantic patch version bumps for Dart projects.
///
/// `DartBump` performs the following steps:
/// - Extracts the current Git diff
/// - Uses ChatGPT to generate a structured CHANGELOG entry
/// - Increments the patch version in `pubspec.yaml`
/// - Prepends the new entry to `CHANGELOG.md`
/// - Updates the API version in `lib/src/api_root.dart`
///
/// All output is routed through [log], which can be overridden
/// for custom logging or silent execution.
class DartBump {
  /// Root directory of the Dart project.
  final Directory projectDir;

  /// Optional map of additional files to update, where:
  /// - **key** is the relative file path (relative to [projectDir])
  /// - **value** is a [RegExp] used to match version strings within that file
  ///
  /// This allows updating multiple extra files beyond the main target, using
  /// custom regex patterns for each file.
  ///
  /// Example:
  /// ```dart
  /// extraFiles: {
  ///   'package.json': RegExp(r'("version":\s*")(\d+\.\d+\.\d+)(")'),
  ///   'README.md': RegExp(r'Version: (\d+\.\d+\.\d+)'),
  /// }
  /// ```
  ///
  /// See also: [updateExtraFiles] for more details on regex format and usage examples.
  final Map<String, RegExp>? extraFiles;

  /// Generator responsible for producing CHANGELOG entries from source changes.
  ///
  /// When provided, it is used to transform a Git patch into a formatted
  /// CHANGELOG entry. If `null`, changelog generation is skipped and a
  /// placeholder entry may be used instead.
  final ChangeLogGenerator? changeLogGenerator;

  DartBump(this.projectDir, {this.extraFiles, this.changeLogGenerator});

  /// Logs informational messages.
  ///
  /// Override to integrate with a custom logger or suppress output.
  void log(String message) {
    print(message);
  }

  /// Increments the patch version in `pubspec.yaml`.
  ///
  /// Example: `1.2.3` → `1.2.4`
  ///
  /// Returns the new version string, or `null` if:
  /// - `pubspec.yaml` does not exist
  /// - No valid version line is found
  String? bumpPatchVersion() {
    final file = File('${projectDir.path}/pubspec.yaml');
    if (!file.existsSync()) return null;

    final content = file.readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+)\.(\d+)\.(\d+)(\S*)',
      multiLine: true,
    ).firstMatch(content);

    if (match == null) return null;

    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    final patch = int.parse(match.group(3)!);
    final dev = match.group(4) ?? '';

    final oldVersion = '$major.$minor.$patch$dev';
    final newVersion = '$major.$minor.${patch + 1}$dev';

    log('🔢 pubspec.yaml: $oldVersion → $newVersion');

    file.writeAsStringSync(
      content.replaceFirst(match.group(0)!, 'version: $newVersion'),
    );

    return newVersion;
  }

  /// Prepends a versioned entry to `CHANGELOG.md`.
  ///
  /// If the file does not exist, it is created.
  /// Always returns `true` once writing succeeds.
  bool updateChangelog(String version, String? changeLogEntry) {
    final file = File('${projectDir.path}/CHANGELOG.md');
    final entry = prepareChangelogEntry(version, changeLogEntry);

    log('📝 Updating CHANGELOG.md');

    if (file.existsSync()) {
      file.writeAsStringSync(entry + file.readAsStringSync());
    } else {
      file.writeAsStringSync(entry);
    }

    return true;
  }

  /// Normalizes a generated CHANGELOG entry.
  ///
  /// - Ensures the version header matches [version]
  /// - Prepends a version header if missing
  /// - Falls back to a placeholder entry if empty
  String prepareChangelogEntry(String version, String? changeLogEntry) {
    if (changeLogEntry == null || changeLogEntry.trim().isEmpty) {
      return '## $version\n\n- ?\n\n';
    }

    final text = changeLogEntry.trim();

    final updated = text.replaceFirst(
      RegExp(r'^##\s+\d+\.\d+\.\d+'),
      '## $version',
    );

    if (!updated.startsWith('## ')) {
      return '## $version\n\n$updated\n\n';
    }

    return '$updated\n\n';
  }

  /// Updates additional project files with the new [version].
  ///
  /// This method handles files beyond `pubspec.yaml` and `api_root.dart`
  /// that should reflect the current project version. Each modified file
  /// is returned in the resulting list.
  ///
  /// Returns a [Future] that completes with a list of updated [File] objects.
  /// If no files were changed, the list will be empty.
  Future<List<File>> updateExtraFiles(String version) async {
    final extraFiles = this.extraFiles;
    if (extraFiles == null || extraFiles.isEmpty) return [];

    var updatedFiles = <File>[];

    for (var e in extraFiles.entries) {
      final relativePath = e.key;
      final regex = e.value;

      final updatedFile = await updateFileVersion(relativePath, version, regex);
      if (updatedFile != null) {
        updatedFiles.add(updatedFile);
      }
    }

    return updatedFiles;
  }

  /// Updates a file at [relativeFilePath] (relative to [projectDir]) by
  /// replacing version strings matching [versionRegex] with [version].
  ///
  /// The replacement behavior depends on the number of capturing groups in [versionRegex]:
  /// - **0 groups**: replaces the entire match with `$version`
  /// - **1 group**: replaces only the captured group while preserving text
  ///   before and after the group
  /// - **2 groups**: replaces with `$g1$version$g2`
  /// - **3 groups**: replaces with `$g1$version$g3`
  ///
  /// Returns the updated [File] if changes were made, or `null` if the file
  /// does not exist or no changes were needed.
  ///
  /// ### Examples:
  ///
  /// ```dart
  /// // 1 group: simple semantic version like 1.2.3
  /// final regex1 = RegExp(r'(\d+\.\d+\.\d+)');
  /// await updateFileVersion('pubspec.yaml', '1.2.4', regex1);
  ///
  /// // 2 groups: version inside quotes, e.g., "version": "1.2.3"
  /// final regex2 = RegExp(r'("version":\s*")\d+\.\d+\.\d+(")');
  /// await updateFileVersion('package.json', '1.2.4', regex2);
  ///
  /// // 3 groups: version with prefix and suffix
  /// final regex3 = RegExp(r'(<version>)(\d+\.\d+\.\d+)(</version>)');
  /// await updateFileVersion('pom.xml', '1.2.4', regex3);
  /// ```
  Future<File?> updateFileVersion(
    String relativeFilePath,
    String version,
    RegExp versionRegex,
  ) async {
    final filePath = p.join(projectDir.path, relativeFilePath);
    final file = File(filePath);

    if (!file.existsSync()) {
      log('⚠️ File not found, skipping update: ${file.path}');
      return null;
    }

    final content = file.readAsStringSync();
    final updated = content.replaceAllMapped(versionRegex, (m) {
      final l = m.groupCount;
      final s = m.group(0) ?? '';
      var replacement = '';
      String? ver;
      if (l == 1) {
        ver = m.group(1)!;
        var verIdx = s.indexOf(ver);
        final before = s.substring(0, verIdx);
        final after = s.substring(verIdx + ver.length);
        replacement = "$before$version$after";
      } else if (l >= 2) {
        var before = m.group(1) ?? '';
        String after;
        if (l >= 3) {
          ver = m.group(2)!;
          after = m.group(3)!;
        } else {
          after = m.group(2)!;
        }
        replacement = "$before$version$after";
      } else {
        replacement = version;
      }

      if (ver != null) {
        log(
          "🔄 Replacing version `$ver` with `$version`:\n✨ `$s` → `$replacement`",
        );
      } else {
        log("🔄 Replacing with version `$version`:\n✨ `$s` → `$replacement`");
      }

      return replacement;
    });

    if (content == updated) return null;

    file.writeAsStringSync(updated);
    print('🔧 Updated file version: ${file.uri.pathSegments.last}');

    return file;
  }

  /// Checks whether the project directory is a Git repository.
  ///
  /// Supports both directory-based and file-based `.git` layouts.
  bool hasGitVersioning() {
    final gitDir = Directory('${projectDir.path}/.git');
    if (gitDir.existsSync()) return true;

    final gitFile = File('${projectDir.path}/.git');
    if (!gitFile.existsSync()) return false;

    return gitFile.readAsStringSync().startsWith('gitdir:');
  }

  /// Extracts the current Git diff using `git diff`.
  ///
  /// Returns `null` if the command fails.
  String? extractGitPatch() {
    final result = runGitCommand(['diff']);
    if (result.exitCode != 0) return null;

    final patch = result.stdout as String;
    log('🧩 Git patch extracted (${patch.length} bytes)');

    return patch;
  }

  /// Executes a Git command synchronously within the project directory.
  ///
  /// [args] are passed directly to the `git` executable (e.g. `['diff']`,
  /// `['status', '--porcelain']`).
  ///
  /// Returns the raw [ProcessResult], including exit code, stdout, and stderr.
  /// The command is executed with `projectDir` as the working directory.
  ProcessResult runGitCommand(List<String> args) {
    return Process.runSync('git', args, workingDirectory: projectDir.path);
  }

  /// Generates a CHANGELOG entry from a source control patch.
  ///
  /// If [patch] is empty or contains only whitespace, `null` is returned.
  /// When a [changeLogGenerator] is configured, the patch is delegated to it
  /// for conversion into a formatted CHANGELOG entry.
  ///
  /// Returns the generated entry, or `null` if generation is skipped or
  /// no generator is available.
  Future<String?> generateChangelogFromPatch(String patch) async {
    if (patch.trim().isEmpty) return null;

    return changeLogGenerator?.generateChangelogFromPatch(patch);
  }

  /// Executes the full version bump workflow.
  ///
  /// Throws if:
  /// - The project directory does not exist
  /// - Git is not detected
  /// - Version bumping fails
  /// - Required files cannot be updated
  ///
  /// Returns the new version and generated CHANGELOG entry.
  Future<({String version, String? changeLogEntry})?> bump() async {
    if (!projectDir.existsSync()) {
      throw 'Project directory does not exist';
    }

    log('📁 Project directory: ${projectDir.absolute.path}');

    if (!hasGitVersioning()) {
      throw 'Git repository not detected';
    }

    log('✔ Git repository detected');

    String? changeLogEntry;
    if (changeLogGenerator != null) {
      log('🧠 $changeLogGenerator — generating CHANGELOG entries...');
      final patch = extractGitPatch();
      if (patch != null) {
        changeLogEntry = await generateChangelogFromPatch(patch);
      }
    } else {
      log(
        '⚠️ No changeLogGenerator defined — skipping CHANGELOG entries generation.',
      );
    }

    final version = bumpPatchVersion();
    if (version == null) {
      throw 'Failed to bump pubspec version';
    }

    if (!updateChangelog(version, changeLogEntry)) {
      throw 'Failed to update CHANGELOG.md';
    }

    var extraFiles = await updateExtraFiles(version);
    if (extraFiles.isNotEmpty) {
      log(
        '📂 Extra files updated:\n${extraFiles.map((f) => f.path).join('\n')}',
      );
    }

    log('🚀 Version bumped to $version');

    return (version: version, changeLogEntry: changeLogEntry);
  }
}

/// Base contract for generating CHANGELOG entries from source control patches.
///
/// Implementations are responsible for converting a textual patch (typically
/// produced by `git diff`) into a formatted CHANGELOG entry, optionally using
/// external services such as AI models.
///
/// Logging is routed through [log], which can be overridden to integrate with
/// custom loggers or silence output.
abstract class ChangeLogGenerator {
  /// API key used to generate CHANGELOG entries.
  ///
  /// If `null` or empty, changelog generation is skipped.
  final String? apiKey;

  /// System prompt used to control the CHANGELOG structure and style.
  ///
  /// This prompt is typically sent as a system message to an AI model.
  final String changelogPrompt;

  /// Default prompt used to generate structured CHANGELOG entries
  /// from a Git patch.
  static const defaultChangelogPrompt =
      '''You are generating a CHANGELOG entry from a git patch.

Follow this exact structure and style:

## <version>

- Short, high-level summary items as bullet points.
- Group related changes under the same class, module, or file name.
- Use backticks for class names, methods, fields, and files.
- For grouped items, use nested bullet points.
- Be concise, technical, and factual.
- Do not invent changes that are not present in the patch.
- Prefer “Added / Updated / Fixed / Removed” wording.

Example output:

## 1.2.3

- New `SomeDomainEntity`.

- `SomeCommandBuilder`:
  - `buildSomething`: added parameter `fooId`.

- `SomeService`:
  - Added field `extraItems`.
  - `fetchItems`:
    - Added parameters `lastItemIds`, `includeExtras`.

- Configuration:
  - Updated default value of `maxRetries`.

- Dependency updates:
  - `http`: ^1.2.0
  - `collection`: ^1.18.0
  - `intl`: ^0.19.0
  ''';

  ChangeLogGenerator({
    this.apiKey,
    this.changelogPrompt = defaultChangelogPrompt,
  });

  /// Generates a CHANGELOG entry from a source control patch.
  ///
  /// [patch] is expected to be a unified diff (e.g. from `git diff`).
  ///
  /// Returns a formatted CHANGELOG entry, or `null` if generation is skipped
  /// or not possible.
  Future<String?> generateChangelogFromPatch(String patch);

  /// Logs informational messages.
  ///
  /// Override to redirect output, integrate with a logger,
  /// or suppress logging entirely.
  void log(String message) {
    print(message);
  }
}

/// CHANGELOG generator backed by the OpenAI Chat Completions API.
///
/// This implementation sends a Git patch to OpenAI and requests a
/// structured CHANGELOG entry based on the configured [changelogPrompt].
///
/// If [apiKey] is `null` or empty, generation is skipped and `null`
/// is returned.
///
/// All operational messages are emitted through [log], which can be
/// overridden for custom logging behavior.
class OpenAIChangeLogGenerator extends ChangeLogGenerator {
  OpenAIChangeLogGenerator({super.apiKey});

  /// Sends a Git patch to ChatGPT and requests a CHANGELOG entry.
  ///
  /// Returns the generated markdown or `null` if:
  /// - The patch is empty
  /// - No API key is configured
  ///
  /// Throws if the OpenAI API returns a non-200 response.
  @override
  Future<String?> generateChangelogFromPatch(String patch) async {
    if (patch.trim().isEmpty) return null;

    final apiKey = this.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      log("❌ No OpenAI API Key! Can't generate CHANGELOG entry!");
      return null;
    }

    final client = HttpClient();
    final request = await client.postUrl(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
    );

    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $apiKey')
      ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');

    request.add(
      utf8.encode(
        jsonEncode({
          'model': 'gpt-4.1-mini',
          'messages': [
            {'role': 'system', 'content': changelogPrompt},
            {'role': 'user', 'content': patch},
          ],
          'temperature': 0.1,
        }),
      ),
    );

    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (response.statusCode != 200) {
      throw 'ChatGPT API error: $body';
    }

    final decoded = jsonDecode(body);
    final genChangeLog = decoded['choices'][0]['message']['content'] as String;

    log('📝 Generated CHANGELOG entry:');
    log('<<$genChangeLog>>');

    return genChangeLog;
  }
}
