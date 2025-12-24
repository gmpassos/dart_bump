/// DartBump: Automated Semantic Versioning for Dart Projects
///
/// This library provides tools to:
/// - Automatically bump patch versions in `pubspec.yaml`
/// - Generate structured CHANGELOG entries from Git patches
/// - Update version references in extra files (e.g., `api_root.dart`)
///
/// Example usage:
/// ```dart
/// final bump = DartBump(Directory.current);
/// bump.bump();
/// ```
///
library;

export 'src/changelog_generator.dart';
export 'src/dart_bump_base.dart';
