#!/usr/bin/env dart

import 'dart:io';

import 'package:args_simple/args_simple_io.dart';
import 'package:dart_bump/dart_bump.dart';

void main(List<String> argsOrig) async {
  var args = ArgsSimple.parse(argsOrig);

  final argHelp =
      args.isEmpty || args.flag('h') || args.options.containsKey('help');

  if (argHelp) {
    showHelp();
    exit(0);
  }

  var projectDirPath = args.argumentAsString(0, Directory.current.path)!;

  var apiKey = args.optionAsString(
    'api-key',
    Platform.environment['OPENAI_API_KEY'],
  );

  // Parse extra file patterns

  final extraFilesArg = args.options['extrafile'];
  final extraFilesArgList = extraFilesArg is List
      ? extraFilesArg.map((e) => e.toString()).toList()
      : [extraFilesArg.toString()];

  final Map<String, RegExp> extraFiles = {};
  for (var e in extraFilesArgList) {
    var item = e.toString();
    var idx = item.indexOf('=');
    if (idx < 1) {
      stderr.writeln(
        '❌ Invalid --extra-file format: $item\nExpected format: filePath=RegExp',
      );
      exit(1);
    }

    var filePath = item.substring(0, idx);
    var re = item.substring(idx + 1);

    try {
      extraFiles[filePath] = RegExp(re);
    } catch (e) {
      stderr.writeln('❌ Invalid --extra-file `$filePath` RegExp: `$re`');
      exit(1);
    }
  }

  ////////////

  final projectDir = Directory(projectDirPath).absolute;

  if (!projectDir.existsSync()) {
    stderr.writeln(
      '❌ Error: Project directory does not exist: ${projectDir.path}',
    );
    exit(1);
  }

  print('\n═════════════════════════[dart_bump]══════════════════════════\n');

  final bump = DartBump(
    projectDir,
    changeLogGenerator: OpenAIChangeLogGenerator(apiKey: apiKey),
    extraFiles: extraFiles,
  );

  try {
    final result = await bump.bump();

    if (result == null) {
      print('⚠️  Nothing to bump - no changes detected.');
      return;
    }

    print('\n══════════════════════════════════════════════════════════════\n');

    if (result.changeLogEntry != null) {
      print(
        '📝  New CHANGELOG entry:\n'
        '────────── CHANGELOG ──────────\n'
        '${result.changeLogEntry}\n'
        '───────────────────────────────',
      );
    }

    if (result.extraFiles.isNotEmpty) {
      print(
        '📂  Extra files updated:\n'
        '   📄  ${result.extraFiles.map((f) => f.path).join('\n   📄  ')}',
      );
    }

    print('🎯  New version: ${result.version}');
    exit(0);
  } catch (e, s) {
    stderr.writeln('❌  Error: $e');
    stderr.writeln(s);
    exit(1);
  }
}

void showHelp() {
  print(r'''
[dart_bump] – 🚀 Smart Version Bumping for Dart Projects

USAGE:
  $ dart_bump [<project-dir>] [--api-key <key>] [options]

OPTIONS:
  %project-dir                 📂 Dart project directory (default: current directory)
  --api-key <key>              🔑 OpenAI API key (default: $OPENAI_API_KEY)
  --extra-file <file=regexp>   🗂️ Specify extra files to bump with a Dart RegExp (multiple allowed)
  -h, --help                   ❓ Show this help message

''');
}
