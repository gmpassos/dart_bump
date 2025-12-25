import 'dart:io';

import 'package:dart_bump/dart_bump.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    print('---------------------------------------');
    tempDir = Directory.systemTemp.createTempSync('dart_bump_test');
    Directory('${tempDir.path}/lib/src').createSync(recursive: true);

    File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_project
version: 1.0.0
''');

    File('${tempDir.path}/lib/src/api_root.dart').writeAsStringSync('''
class ApiRoot {
  ApiRoot() : super('api', '1.0.0');
}
''');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('bumpPatchVersion increments patch correctly', () {
    final bump = DartBump(tempDir);
    final bumpResult = bump.bumpVersion();
    expect(bumpResult, isNotNull);

    var (oldVersion, newVersion) = bumpResult!;

    expect(oldVersion, '1.0.0');
    expect(newVersion, '1.0.1');

    final pubspec = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.1'));
  });

  test('bump updates version and CHANGELOG correctly', () async {
    final changeLogGenerator = TestChangeLogGenerator();

    final bump = TestDartBump(
      tempDir,
      changeLogGenerator: changeLogGenerator,
      gitDiff: 'diff --git a/lib/foo.dart b/lib/foo.dart\n+void foo() {}',
    );

    final result = await bump.bump();

    expect(result, isNotNull);
    expect(result!.version, '1.0.1');
    expect(result.changeLogEntry, contains('Test change generated'));

    final changelog = File('${tempDir.path}/CHANGELOG.md').readAsStringSync();
    expect(changelog, contains('## 1.0.1'));
    expect(changelog, contains('Test change generated'));

    expect(changeLogGenerator.receivedPatches.length, 1);
    expect(bump.logs.any((l) => l.contains('Git patch extracted')), isTrue);
    expect(bump.logs.any((l) => l.contains('Created CHANGELOG.md')), isTrue);
    expect(bump.logs.any((l) => l.contains('Version bumped to 1.0.1')), isTrue);
  });

  test('bump handles empty patch gracefully', () async {
    final changeLogGenerator = TestChangeLogGenerator();

    final bump = TestDartBump(
      tempDir,
      changeLogGenerator: changeLogGenerator,
      gitDiff: '',
    );

    final result = await bump.bump();

    expect(result, isNotNull);
    expect(result!.version, '1.0.1');
    expect(changeLogGenerator.receivedPatches, isEmpty);

    final changelog = File('${tempDir.path}/CHANGELOG.md').readAsStringSync();
    expect(changelog, contains('## 1.0.1'));
    expect(changelog, contains('- ?')); // default entry for empty patch

    expect(
      bump.logs.any((l) => l.contains('Git patch extracted (0 bytes)')),
      isTrue,
    );

    expect(
      bump.logs.any(
        (l) => l.contains('Empty patch, no CHANGELOG to generate.'),
      ),
      isTrue,
    );

    expect(bump.logs.any((l) => l.contains('Version bumped to 1.0.1')), isTrue);
  });

  test(
    'updateExtraFiles updates matching versions including api_root.dart',
    () async {
      final extraFile = File('${tempDir.path}/lib/src/version_file.dart');
      extraFile.writeAsStringSync("const version = '1.0.0';");

      final bump = DartBump(
        tempDir,
        extraFiles: {
          'lib/src/version_file.dart': RegExp(r"const version = '([^']+)'"),
          'lib/src/api_root.dart': RegExp(r"'(\d+\.\d+\.\d+)'"),
        },
      );

      final updatedFiles = await bump.updateExtraFiles('1.0.1');

      // Both files updated
      expect(updatedFiles.length, 2);

      final versionFileContent = extraFile.readAsStringSync();
      expect(versionFileContent, contains("const version = '1.0.1'"));

      final apiRootContent = File(
        '${tempDir.path}/lib/src/api_root.dart',
      ).readAsStringSync();
      expect(apiRootContent, contains("'1.0.1'"));
    },
  );

  test('bump uses last Git tag when gitDiffTag is "last"', () async {
    final changeLogGenerator = TestChangeLogGenerator();

    final bump = TestDartBump(
      tempDir,
      changeLogGenerator: changeLogGenerator,
      gitDiffTag: 'last',
      tags: ['v1.2.1', 'v1.2.0', 'v1.1.5', 'v1.0.0'],
      gitDiff: 'diff --git a/lib/foo.dart b/lib/foo.dart\n+void foo() {}',
    );

    final result = await bump.bump();

    expect(result, isNotNull);

    expect(
      bump.logs.any(
        (l) => l.contains('Git tags: [v1.2.1, v1.2.0, v1.1.5, v1.0.0]'),
      ),
      isTrue,
    );

    expect(bump.logs.any((l) => l.contains('Last Git tag: v1.2.1')), isTrue);

    expect(
      bump.logs.any(
        (l) => l.contains('Git patch extracted from tag <v1.2.1> (55 bytes)'),
      ),
      isTrue,
    );
  });

  test('dryRun does not modify files or write CHANGELOG', () async {
    final changeLogGenerator = TestChangeLogGenerator();

    final bump = TestDartBump(
      tempDir,
      changeLogGenerator: changeLogGenerator,
      gitDiff: 'diff --git a/lib/foo.dart b/lib/foo.dart\n+void foo() {}',
      dryRun: true,
    );

    final result = await bump.bump();

    expect(result, isNotNull);
    expect(result!.version, '1.0.1');

    // pubspec.yaml NOT modified
    final pubspec = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.0'));

    // CHANGELOG.md NOT created
    expect(File('${tempDir.path}/CHANGELOG.md').existsSync(), isFalse);

    // CHANGELOG generator still runs
    expect(changeLogGenerator.receivedPatches.length, 1);

    // Logs indicate dry run
    expect(
      bump.logs.any(
        (l) => l.contains('Dry run mode — no files will be modified'),
      ),
      isTrue,
    );

    expect(
      bump.logs.any((l) => l.contains('[SKIP] pubspec.yaml: 1.0.0 → 1.0.1')),
      isTrue,
    );
    expect(
      bump.logs.any((l) => l.contains('[SKIP] Updated CHANGELOG.md')),
      isTrue,
    );
  });

  test('updateExtraFiles does not modify files in dry run mode', () async {
    final extraFile = File('${tempDir.path}/lib/src/version_file.dart');
    extraFile.writeAsStringSync("const version = '1.0.0';");

    final bump = DartBump(
      tempDir,
      dryRun: true,
      extraFiles: {
        'lib/src/version_file.dart': RegExp(r"const version = '([^']+)'"),
        'lib/src/api_root.dart': RegExp(r"'(\d+\.\d+\.\d+)'"),
      },
    );

    final updatedFiles = await bump.updateExtraFiles('1.0.1');

    // Files are detected but NOT written
    expect(updatedFiles.length, 2);

    final versionFileContent = extraFile.readAsStringSync();
    expect(versionFileContent, contains("const version = '1.0.0'"));

    final apiRootContent = File(
      '${tempDir.path}/lib/src/api_root.dart',
    ).readAsStringSync();
    expect(apiRootContent, contains("'1.0.0'"));
  });

  test('--no-bump does not change version', () async {
    final bump = TestDartBump(
      tempDir,
      gitDiff: 'diff --git a/lib/foo.dart b/lib/foo.dart\n+void foo() {}',
      noBump: true,
    );

    final result = await bump.bump();

    expect(result, isNotNull);
    expect(result!.version, '1.0.0');

    final pubspec = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.0'));

    expect(
      bump.logs.any(
        (l) => l.contains(
          '[SKIP] Version bump skipped for `1.0.0` in `pubspec.yaml`. (--no-bump)',
        ),
      ),
      isTrue,
    );
  });

  test('--no-changelog skips CHANGELOG generation', () async {
    final changeLogGenerator = TestChangeLogGenerator();

    final bump = TestDartBump(
      tempDir,
      changeLogGenerator: changeLogGenerator,
      gitDiff: 'diff --git a/lib/foo.dart b/lib/foo.dart\n+void foo() {}',
      noChangelog: true,
    );

    final result = await bump.bump();

    expect(result, isNotNull);
    expect(result!.version, '1.0.1');

    expect(File('${tempDir.path}/CHANGELOG.md').existsSync(), isFalse);
    expect(changeLogGenerator.receivedPatches, isEmpty);

    expect(
      bump.logs.any(
        (l) => l.contains('[SKIP] Skipping CHANGELOG update. (--no-changelog)'),
      ),
      isTrue,
    );
  });

  test('--no-extra skips extra file updates', () async {
    final extraFile = File('${tempDir.path}/lib/src/version_file.dart');
    extraFile.writeAsStringSync("const version = '1.0.0';");

    final bump = TestDartBump(
      tempDir,
      noExtra: true,
      extraFiles: {
        'lib/src/version_file.dart': RegExp(r"const version = '([^']+)'"),
        'lib/src/api_root.dart': RegExp(r"'(\d+\.\d+\.\d+)'"),
      },
    );

    final updatedFiles = await bump.updateExtraFiles('1.0.1');

    expect(updatedFiles, isEmpty);

    expect(extraFile.readAsStringSync(), contains("const version = '1.0.0'"));

    final apiRootContent = File(
      '${tempDir.path}/lib/src/api_root.dart',
    ).readAsStringSync();
    expect(apiRootContent, contains("'1.0.0'"));

    expect(
      bump.logs.any(
        (l) => l.contains('[SKIP] Skipping 2 extra files update. (--no-extra)'),
      ),
      isTrue,
    );
  });

  group('VersionBumpType', () {
    test('TestDartBump(patch)', () async {
      final bump = TestDartBump(
        tempDir,
        versionBumpType: VersionBumpType.patch,
      );

      final result = await bump.bump();

      expect(result, isNotNull);
      expect(result!.version, '1.0.1');

      final pubspec = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('version: 1.0.1'));
    });

    test('TestDartBump(minor)', () async {
      final bump = TestDartBump(
        tempDir,
        versionBumpType: VersionBumpType.minor,
      );

      final result = await bump.bump();

      expect(result, isNotNull);
      expect(result!.version, '1.1.0');

      final pubspec = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('version: 1.1.0'));
    });

    test('TestDartBump(major)', () async {
      final bump = TestDartBump(
        tempDir,
        versionBumpType: VersionBumpType.major,
      );

      final result = await bump.bump();

      expect(result, isNotNull);
      expect(result!.version, '2.0.0');

      final pubspec = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('version: 2.0.0'));
    });

    group('VersionBumpType.bump()', () {
      test('patch bump increments patch only', () {
        final v = VersionBumpType.patch.bump(1, 2, 3);
        print(v);
        expect(v, '1.2.4');
      });

      test('minor bump increments minor and resets patch', () {
        final v = VersionBumpType.minor.bump(1, 2, 3);
        print(v);
        expect(v, '1.3.0');
      });

      test('major bump increments major and resets minor and patch', () {
        final v = VersionBumpType.major.bump(1, 2, 3);
        print(v);
        expect(v, '2.0.0');
      });

      test('patch bump preserves dev suffix', () {
        final v = VersionBumpType.patch.bump(1, 2, 3, '-dev.1');
        print(v);
        expect(v, '1.2.4-dev.1');
      });

      test('minor bump preserves dev suffix', () {
        final v = VersionBumpType.minor.bump(1, 2, 3, '-beta');
        print(v);
        expect(v, '1.3.0-beta');
      });

      test('major bump preserves dev suffix', () {
        final v = VersionBumpType.major.bump(1, 2, 3, '-rc.1');
        print(v);
        expect(v, '2.0.0-rc.1');
      });
    });

    group('VersionBumpType.resolve()', () {
      test('returns major when major=true', () {
        final t = VersionBumpType.resolve(major: true);
        print(t);
        expect(t, VersionBumpType.major);
      });

      test('returns minor when minor=true', () {
        final t = VersionBumpType.resolve(minor: true);
        print(t);
        expect(t, VersionBumpType.minor);
      });

      test('returns patch when patch=true', () {
        final t = VersionBumpType.resolve(patch: true);
        print(t);
        expect(t, VersionBumpType.patch);
      });

      test('major has priority over minor and patch', () {
        final t = VersionBumpType.resolve(
          major: true,
          minor: true,
          patch: true,
        );
        print(t);
        expect(t, VersionBumpType.major);
      });

      test('minor has priority over patch', () {
        final t = VersionBumpType.resolve(minor: true, patch: true);
        print(t);
        expect(t, VersionBumpType.minor);
      });

      test('defaults to patch when all flags are null', () {
        final t = VersionBumpType.resolve();
        print(t);
        expect(t, VersionBumpType.patch);
      });

      test('defaults to patch when all flags are false', () {
        final t = VersionBumpType.resolve(
          major: false,
          minor: false,
          patch: false,
        );
        print(t);
        expect(t, VersionBumpType.patch);
      });
    });
  });
}

/// Mock CHANGELOG generator for tests
class TestChangeLogGenerator extends ChangeLogGenerator {
  final List<String> logs = [];
  final List<String> receivedPatches = [];

  TestChangeLogGenerator();

  @override
  Future<String?> generateChangelogFromPatch(String patch) async {
    if (patch.isEmpty) return null;
    receivedPatches.add(patch);
    logs.add('Generating CHANGELOG for patch of length ${patch.length}');
    return '''
## 1.0.1

- Test change generated from mock patch.
''';
  }

  @override
  void log(String message) {
    logs.add(message);
    print('» $message');
  }
}

class TestDartBump extends DartBump {
  final List<String> logs = [];

  final String gitDiff;

  final List<String> tags;

  TestDartBump(
    super.projectDir, {
    super.changeLogGenerator,
    super.extraFiles,
    this.gitDiff = '',
    this.tags = const [],
    super.gitDiffTag,
    super.versionBumpType,
    super.noBump,
    super.noChangelog,
    super.noExtra,
    super.dryRun,
  });

  @override
  void log(String message) {
    logs.add(message);
    print('» $message');
  }

  @override
  bool hasGitVersioning() => true;

  @override
  ProcessResult runGitCommand(List<String> args) {
    if (args.isNotEmpty) {
      final arg0 = args.first;
      if (arg0 == 'tag') {
        return ProcessResult(0, 0, tags.join('\n'), '');
      } else if (arg0 == 'diff') {
        return ProcessResult(0, 0, gitDiff, '');
      }
    }

    return ProcessResult(0, 0, '', '');
  }

  @override
  String toString() =>
      'TestDartBump'
      '#$hashCode'
      '${changeLogGenerator != null ? '[$changeLogGenerator]' : ''}'
      '@$projectDir';
}
