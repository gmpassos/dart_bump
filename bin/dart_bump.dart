#!/usr/bin/env dart

import 'dart:io';

import 'package:dart_bump/dart_bump.dart';

void printUsage() {
  print('''
Usage: dart_bump [options]

Options:
  --project-dir <path>   Path to the Dart project (default: current directory)
  --api-key <key>        OpenAI API key (optional; defaults to OPENAI_API_KEY env)
  -h, --help             Show this help message
''');
}

Future<void> main(List<String> args) async {
  String? projectDirPath;
  String? apiKey;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-h':
      case '--help':
        printUsage();
        return;
      case '--project-dir':
        if (i + 1 < args.length) {
          projectDirPath = args[++i];
        } else {
          stderr.writeln('Error: --project-dir requires a path.');
          exit(1);
        }
        break;
      case '--api-key':
        if (i + 1 < args.length) {
          apiKey = args[++i];
        } else {
          stderr.writeln('Error: --api-key requires a value.');
          exit(1);
        }
        break;
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        printUsage();
        exit(1);
    }
  }

  final projectDir = Directory(projectDirPath ?? Directory.current.path);

  if (!projectDir.existsSync()) {
    stderr.writeln(
      'Error: Project directory does not exist: ${projectDir.path}',
    );
    exit(1);
  }

  final bump = DartBump(
    projectDir,
    changeLogGenerator: OpenAIChangeLogGenerator(
      apiKey: apiKey ?? Platform.environment['OPENAI_API_KEY'],
    ),
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
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}
