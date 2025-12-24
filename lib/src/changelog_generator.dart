import 'dart:convert';
import 'dart:io';

/// Base contract for generating CHANGELOG entries from source control patches.
///
/// Implementations are responsible for converting a textual patch (typically
/// produced by `git diff`) into a formatted CHANGELOG entry, optionally using
/// external services such as AI models.
///
/// Logging is routed through [log], which can be overridden to integrate with
/// custom loggers or silence output.
abstract class ChangeLogGenerator {
  /// API key used to generate CHANGELOG entries.
  ///
  /// If `null` or empty, changelog generation is skipped.
  final String? apiKey;

  /// System prompt used to control the CHANGELOG structure and style.
  ///
  /// This prompt is typically sent as a system message to an AI model.
  final String changelogPrompt;

  /// Default prompt used to generate structured CHANGELOG entries
  /// from a Git patch.
  static const defaultChangelogPrompt =
      '''You are generating a CHANGELOG entry from a git patch.

Follow this exact structure and style:

## <version>

- Short, high-level summary items as bullet points.
- Group related changes under the same class, module, or file name.
- Use backticks for class names, methods, fields, and files.
- For grouped items, use nested bullet points.
- Be concise, technical, and factual.
- Do not invent changes that are not present in the patch.
- Prefer “Added / Updated / Fixed / Removed” wording.

Example output:

## 1.2.3

- New `SomeDomainEntity`.

- `SomeCommandBuilder`:
  - `buildSomething`: added parameter `fooId`.

- `SomeService`:
  - Added field `extraItems`.
  - `fetchItems`:
    - Added parameters `lastItemIds`, `includeExtras`.

- Configuration:
  - Updated default value of `maxRetries`.

- Dependency updates:
  - `http`: ^1.2.0
  - `collection`: ^1.18.0
  - `intl`: ^0.19.0
  ''';

  ChangeLogGenerator({
    this.apiKey,
    this.changelogPrompt = defaultChangelogPrompt,
  });

  /// Generates a CHANGELOG entry from a source control patch.
  ///
  /// [patch] is expected to be a unified diff (e.g. from `git diff`).
  ///
  /// Returns a formatted CHANGELOG entry, or `null` if generation is skipped
  /// or not possible.
  Future<String?> generateChangelogFromPatch(String patch);

  /// Logs informational messages.
  ///
  /// Override to redirect output, integrate with a logger,
  /// or suppress logging entirely.
  void log(String message) {
    print(message);
  }

  @override
  String toString() {
    final apiKey = this.apiKey;
    return apiKey != null
        ? '$runtimeType#$hashCode{'
              'apiKey: ${'*' * apiKey.length}'
              '}'
        : '$runtimeType#$hashCode';
  }
}

/// CHANGELOG generator backed by the OpenAI Chat Completions API.
///
/// This implementation sends a Git patch to OpenAI and requests a
/// structured CHANGELOG entry based on the configured [changelogPrompt].
///
/// If [apiKey] is `null` or empty, generation is skipped and `null`
/// is returned.
///
/// All operational messages are emitted through [log], which can be
/// overridden for custom logging behavior.
class OpenAIChangeLogGenerator extends ChangeLogGenerator {
  OpenAIChangeLogGenerator({super.apiKey});

  /// Sends a Git patch to ChatGPT and requests a CHANGELOG entry.
  ///
  /// Returns the generated markdown or `null` if:
  /// - The patch is empty
  /// - No API key is configured
  ///
  /// Throws if the OpenAI API returns a non-200 response.
  @override
  Future<String?> generateChangelogFromPatch(String patch) async {
    if (patch.trim().isEmpty) return null;

    final apiKey = this.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      log("❌ No OpenAI API Key! Can't generate CHANGELOG entry!");
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
            {'role': 'system', 'content': changelogPrompt},
            {'role': 'user', 'content': patch},
          ],
          'temperature': 0.1,
        }),
      ),
    );

    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (response.statusCode != 200) {
      throw 'ChatGPT API error: $body';
    }

    final decoded = jsonDecode(body);
    final genChangeLog = decoded['choices'][0]['message']['content'] as String;

    log('📝 Generated CHANGELOG entry:');
    log('<<$genChangeLog>>');

    return genChangeLog;
  }
}
