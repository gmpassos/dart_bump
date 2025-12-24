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
    final newVersion = bump.bumpPatchVersion();

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
    expect(bump.logs.any((l) => l.contains('Updating CHANGELOG.md')), isTrue);
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
    this.gitDiff = '',
    this.tags = const [],
    super.gitDiffTag,
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
