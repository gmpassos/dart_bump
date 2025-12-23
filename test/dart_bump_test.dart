import 'dart:io';

import 'package:dart_bump/dart_bump.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dart_bump_test');
    Directory('${tempDir.path}/lib/src').createSync(recursive: true);

    // Minimal pubspec.yaml
    File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_project
version: 1.0.0
''');

    // Minimal api_root.dart
    File('${tempDir.path}/lib/src/api_root.dart').writeAsStringSync('''
class ApiRoot {
  ApiRoot() : super('api', '1.0.0');
}
''');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('bump updates version and generates CHANGELOG', () async {
    final changeLogGenerator = TestChangeLogGenerator();

    final bump = TestDartBump(
      tempDir,
      changeLogGenerator: changeLogGenerator,
      gitDiff: '''
diff --git a/lib/foo.dart b/lib/foo.dart
+void foo() {}
''',
    );

    final result = await bump.bump();

    // Verify bump result
    expect(result, isNotNull);
    expect(result!.version, '1.0.1');
    expect(result.changeLogEntry, contains('Test change generated'));

    // Verify generator was called
    expect(changeLogGenerator.receivedPatches.length, 1);

    // Verify logs captured
    expect(bump.logs.any((l) => l.contains('Git patch extracted')), isTrue);
    expect(bump.logs.any((l) => l.contains('Version bumped')), isTrue);
    expect(
      changeLogGenerator.logs.any(
        (l) => l.contains('Generating CHANGELOG for patch'),
      ),
      isTrue,
    );
  });

  test('bump handles empty patch gracefully', () async {
    final changeLogGenerator = TestChangeLogGenerator();

    final bump = TestDartBump(
      tempDir,
      changeLogGenerator: changeLogGenerator,
      gitDiff: '',
    );

    final result = await bump.bump();

    // Version should still be bumped
    expect(result, isNotNull);
    expect(result!.version, '1.0.1');

    // No patch sent to generator
    expect(changeLogGenerator.receivedPatches, isEmpty);

    // Logs should indicate skipping generation
    expect(bump.logs.any((l) => l.contains('Git patch extracted')), isTrue);
  });
}

/// Simple CHANGELOG generator used for testing.
class TestChangeLogGenerator extends ChangeLogGenerator {
  final List<String> logs = [];
  final List<String> receivedPatches = [];

  TestChangeLogGenerator();

  @override
  Future<String?> generateChangelogFromPatch(String patch) async {
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
  }
}

class TestDartBump extends DartBump {
  final List<String> logs = [];
  final String gitDiff;

  TestDartBump(
    super.projectDir, {
    super.changeLogGenerator,
    required this.gitDiff,
  });

  @override
  void log(String message) {
    logs.add(message);
  }

  @override
  bool hasGitVersioning() => true;

  @override
  ProcessResult runGitCommand(List<String> args) {
    if (args.length == 1 && args.first == 'diff') {
      return ProcessResult(0, 0, gitDiff, '');
    }
    return ProcessResult(0, 0, '', '');
  }
}
