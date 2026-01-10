import 'dart:convert';
import 'dart:io';

/// Base contract for generating Git branch name suggestions
/// from a CHANGELOG entry.
///
/// Implementations are responsible for converting a formatted
/// CHANGELOG (markdown) into a list of valid Git branch names.
///
/// Suggestions should follow common Git conventions such as:
/// - lowercase
/// - hyphen-separated
/// - concise but descriptive
///
/// Logging is routed through [log] and can be overridden.
abstract class BranchNameGenerator {
  /// API key used to generate branch name suggestions.
  ///
  /// If `null` or empty, generation is skipped.
  final String? apiKey;

  /// Maximum number of branch name suggestions to generate.
  final int maxSuggestions;

  /// System prompt used to control branch name generation.
  static const defaultBranchPrompt = '''
You are generating Git branch name suggestions from a CHANGELOG entry.

Rules:
- Output MUST be a JSON array of strings.
- Each string is a valid Git branch name.
- Use lowercase letters and hyphens only.
- Do not include spaces.
- Be concise and descriptive.
- Prefer prefixes like:
  - feature/
  - fix/
  - refactor/
  - chore/
- Base suggestions strictly on the CHANGELOG content.
- Do not add explanations or extra text.

Example output:
[
  "feature/add-inventory-snapshot",
  "fix/email-delivery-timeout",
  "refactor/dns-client-lookups"
]
''';

  final String branchPrompt;

  BranchNameGenerator({
    this.apiKey,
    this.maxSuggestions = 5,
    this.branchPrompt = defaultBranchPrompt,
  });

  /// Generates a list of Git branch name suggestions
  /// from a CHANGELOG entry.
  ///
  /// Returns `null` if generation is skipped or not possible.
  Future<List<String>?> generateBranchesFromChangelog(String changelogEntry);

  /// Logs informational messages.
  void log(String message) {
    print(message);
  }

  @override
  String toString() {
    final apiKey = this.apiKey;
    return apiKey != null
        ? '$runtimeType#$hashCode{'
              'apiKey: ${'*' * apiKey.length.clamp(3, 6)}, '
              'maxSuggestions: $maxSuggestions'
              '}'
        : '$runtimeType#$hashCode{maxSuggestions: $maxSuggestions}';
  }
}

/// Branch name generator backed by the OpenAI Chat Completions API.
///
/// This implementation sends a CHANGELOG entry to OpenAI
/// and expects a JSON array of branch name suggestions.
class OpenAIBranchNameGenerator extends BranchNameGenerator {
  OpenAIBranchNameGenerator({super.apiKey, super.maxSuggestions});

  @override
  Future<List<String>?> generateBranchesFromChangelog(
    String changelogEntry,
  ) async {
    if (changelogEntry.trim().isEmpty) return null;

    final apiKey = this.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      log("❌  No OpenAI API Key! Can't generate branch names!");
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
            {'role': 'system', 'content': branchPrompt},
            {
              'role': 'user',
              'content':
                  '''
Limit suggestions to $maxSuggestions.

CHANGELOG:
$changelogEntry
''',
            },
          ],
          'temperature': 0.1,
        }),
      ),
    );

    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (response.statusCode != 200) {
      throw 'OpenAI API error: $body';
    }

    final decoded = jsonDecode(body);
    final content = decoded['choices'][0]['message']['content'] as String;

    final parsed = _jsonDecode<List>(content);
    final branches = parsed?.nonNulls.map((e) => '$e').toList();

    if (branches == null || branches.isEmpty) {
      log('⚠️ NO branch name list generated.');
      return null;
    }

    log(
      '🔀  Generated branch suggestions (${branches.length}):\n'
      '${branches.map((b) => ' - $b').join('\n')}',
    );

    return branches;
  }

  T? _jsonDecode<T>(String input) {
    input = input.trim();
    if (input.isEmpty) return null;

    Object? j;
    try {
      j = json.decode(input);
    } catch (e) {
      log(
        "❌ Error decoding JSON:\n"
        "-- ERROR: $e\n"
        "-- INPUT:\n$input",
      );
      return null;
    }

    if (j == null) return null;

    if (j is! T) {
      log(
        "❌ Error decoding JSON: Can't cast to `$T`\n"
        "-- DECODED: $j\n"
        "-- INPUT:\n$input",
      );
      return null;
    }

    return j as T;
  }
}
