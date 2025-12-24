import 'dart:io';

import 'package:path/path.dart' as p;

import 'changelog_generator.dart';

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

    log('🔢  pubspec.yaml: $oldVersion → $newVersion');

    file.writeAsStringSync(
      content.replaceFirst(match.group(0)!, 'version: $newVersion'),
    );

    return newVersion;
  }

  /// Prepends a versioned entry to `CHANGELOG.md`.
  ///
  /// If the file does not exist, it is created.
  /// Always returns `true` once writing succeeds.
  String updateChangelog(String version, String? changeLogEntry) {
    final file = File('${projectDir.path}/CHANGELOG.md');
    final changeLogEntryVersioned = prepareChangelogEntry(
      version,
      changeLogEntry,
    );

    log('📝  Updating CHANGELOG.md');

    if (file.existsSync()) {
      file.writeAsStringSync(changeLogEntryVersioned + file.readAsStringSync());
    } else {
      file.writeAsStringSync(changeLogEntryVersioned);
    }

    return changeLogEntryVersioned;
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
    final filePath = p.normalize(p.join(projectDir.path, relativeFilePath));
    final file = File(filePath);

    if (!file.existsSync()) {
      log('⚠️  File not found, skipping update: ${file.path}');
      return null;
    }

    final fileName = file.uri.pathSegments.last;

    final content = file.readAsStringSync();

    final updated = content.replaceFirstMapped(versionRegex, (m) {
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
          "📄  $fileName:\n   🔄  Replacing version `$ver` with `$version`:\n   ✨ `$s` → `$replacement`",
        );
      } else {
        log(
          "📄  $fileName:\n   🔄  Replacing with version `$version`:\n   ✨ `$s` → `$replacement`",
        );
      }

      return replacement;
    });

    if (content == updated) return null;

    file.writeAsStringSync(updated);

    print('   🔧  Updated file version: $fileName');

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
    log('🧩  Git patch extracted (${patch.length} bytes)');

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
  Future<({String version, String? changeLogEntry, List<File> extraFiles})?>
  bump() async {
    if (!projectDir.existsSync()) {
      throw 'Project directory does not exist';
    }

    log('📁  Project directory: ${projectDir.absolute.path}');

    if (!hasGitVersioning()) {
      throw 'Git repository not detected';
    }

    log('✔  Git repository detected');

    String? changeLogEntry;
    if (changeLogGenerator != null) {
      final patch = extractGitPatch();
      if (patch != null && patch.isNotEmpty) {
        log('🧠  $changeLogGenerator — generating CHANGELOG entries...');
        changeLogEntry = await generateChangelogFromPatch(patch);
      } else {
        log('⚠️  Empty patch, no CHANGELOG to generate.');
      }
    } else {
      log(
        '⚠️  No changeLogGenerator defined — skipping CHANGELOG entries generation.',
      );
    }

    final version = bumpPatchVersion();
    if (version == null) {
      throw 'Failed to bump pubspec version';
    }

    var updatedChangeLogEntry = updateChangelog(version, changeLogEntry);

    var extraFiles = await updateExtraFiles(version);

    log('🚀  Version bumped to $version');

    return (
      version: version,
      changeLogEntry: updatedChangeLogEntry,
      extraFiles: extraFiles,
    );
  }
}
