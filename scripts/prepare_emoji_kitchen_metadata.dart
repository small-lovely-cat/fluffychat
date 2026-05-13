import 'dart:convert';
import 'dart:io';

const String _outputPath = 'assets/emoji_kitchen/metadata.json';
const List<String> _defaultMetadataUrls = <String>[
  'https://cdn.jsdelivr.net/gh/xsalazar/emoji-kitchen-backend@main/app/metadata.json',
  'https://raw.githubusercontent.com/xsalazar/emoji-kitchen-backend/main/app/metadata.json',
];

Future<void> main() async {
  final outputFile = File(_outputPath);
  final urls = _resolveMetadataUrls();

  stdout.writeln('Preparing Emoji Kitchen metadata...');
  stdout.writeln('Output: ${outputFile.path}');

  for (final url in urls) {
    stdout.writeln('Trying source: $url');
    try {
      final json = await _downloadAndValidateMetadata(url);
      await outputFile.parent.create(recursive: true);
      final prettyJson = const JsonEncoder.withIndent('  ').convert(json);
      await outputFile.writeAsString('$prettyJson\n');
      stdout.writeln(
        'Emoji Kitchen metadata updated successfully from $url',
      );
      return;
    } catch (error, stackTrace) {
      stderr.writeln('Failed to fetch metadata from $url');
      stderr.writeln(error);
      stderr.writeln(stackTrace);
    }
  }

  if (await _hasValidLocalMetadata(outputFile)) {
    stdout.writeln(
      'All remote sources failed. Keeping existing local metadata asset.',
    );
    return;
  }

  stderr.writeln(
    'Unable to prepare Emoji Kitchen metadata and no valid local fallback exists.',
  );
  exitCode = 1;
}

/// 解析元数据下载地址列表。
///
/// Args:
///   无。
///
/// Returns:
///   按优先级排序的下载地址列表。
List<String> _resolveMetadataUrls() {
  final envValue = Platform.environment['EMOJI_KITCHEN_METADATA_URLS'];
  if (envValue == null || envValue.trim().isEmpty) {
    return _defaultMetadataUrls;
  }
  return envValue
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// 下载并校验 Emoji Kitchen 元数据。
///
/// Args:
///   url: 元数据地址。
///
/// Returns:
///   通过校验的 JSON 对象。
///
/// Raises:
///   HttpException: 当请求失败时抛出。
///   FormatException: 当 JSON 结构不合法时抛出。
Future<Map<String, dynamic>> _downloadAndValidateMetadata(String url) async {
  final httpClient = HttpClient();
  try {
    final request = await httpClient.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Unexpected status code ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Metadata root must be a JSON object.');
    }
    _validateMetadataJson(json);
    return json;
  } finally {
    httpClient.close(force: true);
  }
}

/// 判断本地现有元数据是否可作为兜底使用。
///
/// Args:
///   outputFile: 本地元数据文件。
///
/// Returns:
///   当文件存在且结构合法时返回 true。
Future<bool> _hasValidLocalMetadata(File outputFile) async {
  if (!await outputFile.exists()) {
    return false;
  }
  try {
    final content = await outputFile.readAsString();
    final json = jsonDecode(content);
    if (json is! Map<String, dynamic>) {
      return false;
    }
    _validateMetadataJson(json);
    return true;
  } catch (_) {
    return false;
  }
}

/// 校验元数据 JSON 结构。
///
/// Args:
///   json: 待校验的元数据对象。
///
/// Returns:
///   无返回值。
///
/// Raises:
///   FormatException: 当关键字段缺失或类型错误时抛出。
void _validateMetadataJson(Map<String, dynamic> json) {
  final knownSupportedEmoji = json['knownSupportedEmoji'];
  final data = json['data'];

  if (knownSupportedEmoji is! List) {
    throw const FormatException('knownSupportedEmoji must be a JSON array.');
  }
  if (data is! Map<String, dynamic>) {
    throw const FormatException('data must be a JSON object.');
  }

  for (final entry in data.entries.take(5)) {
    final emojiData = entry.value;
    if (emojiData is! Map<String, dynamic>) {
      throw FormatException('Emoji data for ${entry.key} must be an object.');
    }
    if (emojiData['combinations'] is! Map<String, dynamic>) {
      throw FormatException(
        'Emoji data for ${entry.key} is missing combinations.',
      );
    }
  }
}
