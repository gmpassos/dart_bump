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

  final projectDir = Directory(projectDirPath).absolute;

  if (!projectDir.existsSync()) {
    stderr.writeln(
      '❌ Error: Project directory does not exist: ${projectDir.path}',
    );
    exit(1);
  }

  final bump = DartBump(
    projectDir,
    changeLogGenerator: OpenAIChangeLogGenerator(apiKey: apiKey),
  );

  try {
    final result = await bump.bump();

    if (result == null) {
      print('Nothing to bump.');
      return;
    }

    print('🚀 Version bumped to ${result.version}');

    if (result.changeLogEntry != null) {
      print('📝 Generated CHANGELOG entry:\n${result.changeLogEntry}');
    }
  } catch (e, s) {
    stderr.writeln('❌ Error: $e');
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
  %project-dir           📂 Dart project directory (default: current directory)
  --api-key <key>        🔑 OpenAI API key (default: $OPENAI_API_KEY)
  -h, --help             ❓ Show this help message

''');
}
