import 'dart:io';

import 'package:dart_bump/dart_bump.dart';

/// Usage:
/// dart dart_bump_example.dart [projectDir] [openaiApiKey]
///
/// - projectDir: path to the Dart project (defaults to current directory)
/// - openaiApiKey: OpenAI API key (optional; falls back to OPENAI_API_KEY env)
Future<void> main(List<String> args) async {
  final projectDir = Directory(
    args.isNotEmpty ? args[0] : Directory.current.path,
  );

  final apiKey = args.length > 1
      ? args[1]
      : Platform.environment['OPENAI_API_KEY'];

  final bump = DartBump(
    projectDir,
    changeLogGenerator: OpenAIChangeLogGenerator(apiKey: apiKey),
  );

  try {
    final result = await bump.bump();
    if (result == null) {
      print('❌ Nothing to bump.');
      return;
    }

    if (result.changeLogEntry != null) {
      print('🚀 Bump successful!');
    }
  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
}
