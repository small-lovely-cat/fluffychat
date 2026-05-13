import 'dart:convert';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/utils/emoji/latest_emoji_set.dart';
import 'package:flutter/services.dart';

/// Emoji Kitchen 本地打包元数据路径。
const String kEmojiKitchenMetadataAssetPath =
    'assets/emoji_kitchen/metadata.json';

/// Emoji Kitchen 元数据加载与查询服务。
class EmojiKitchenService {
  static Future<EmojiKitchenMetadata>? _metadataFuture;

  /// 加载 Emoji Kitchen 元数据。
  ///
  /// Returns: 已解析完成的元数据对象。
  /// Throws: 当资源文件缺失或返回内容无法解析时抛出异常。
  static Future<EmojiKitchenMetadata> loadMetadata() {
    return _metadataFuture ??= _fetchMetadata();
  }

  /// 根据 codepoint 读取可展示的 Emoji 条目。
  ///
  /// - Parameters:
  ///   - emojiCodepoint: Emoji Kitchen 元数据中的 codepoint。
  ///   - fallbackName: 当本地名称表中不存在该 emoji 时使用的兜底名称。
  /// - Returns: 可用于界面展示的 emoji 条目。
  static EmojiKitchenCatalogEntry getCatalogEntry(
    String emojiCodepoint, {
    String? fallbackName,
  }) {
    return _catalogByCodepoint[emojiCodepoint] ??
        EmojiKitchenCatalogEntry(
          emoji: _emojiFromCodepoint(emojiCodepoint),
          emojiCodepoint: emojiCodepoint,
          name: fallbackName ?? emojiCodepoint,
        );
  }

  /// 生成本地图片文件名。
  ///
  /// - Parameters:
  ///   - label: Emoji Kitchen 返回的组合名称。
  /// - Returns: 适合发送图片时使用的文件名。
  static String buildFileName(String label) {
    final sanitized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${sanitized.isEmpty ? 'emoji_mix' : sanitized}.png';
  }

  /// 发起元数据请求并完成 JSON 解析。
  ///
  /// Returns: 已解析的元数据对象。
  /// Throws: 当资源读取失败或解析失败时抛出异常。
  static Future<EmojiKitchenMetadata> _fetchMetadata() async {
    final content = await rootBundle.loadString(kEmojiKitchenMetadataAssetPath);
    final json = jsonDecode(content) as Map<String, dynamic>;
    return EmojiKitchenMetadata.fromJson(json);
  }
}

/// Emoji Kitchen 总元数据对象。
class EmojiKitchenMetadata {
  final List<String> knownSupportedEmoji;
  final Map<String, EmojiKitchenEmojiData> data;

  const EmojiKitchenMetadata({
    required this.knownSupportedEmoji,
    required this.data,
  });

  /// 从 JSON 创建元数据对象。
  ///
  /// - Parameters:
  ///   - json: 远端返回的元数据 JSON。
  /// - Returns: 解析后的元数据对象。
  factory EmojiKitchenMetadata.fromJson(Map<String, dynamic> json) {
    final knownSupportedEmoji = (json['knownSupportedEmoji'] as List<dynamic>)
        .cast<String>();
    final rawData = json['data'] as Map<String, dynamic>;
    return EmojiKitchenMetadata(
      knownSupportedEmoji: knownSupportedEmoji,
      data: rawData.map(
        (key, value) => MapEntry(
          key,
          EmojiKitchenEmojiData.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }

  /// 获取指定 emoji 的所有可混合目标。
  ///
  /// - Parameters:
  ///   - emojiCodepoint: 当前选中的左侧 emoji codepoint。
  /// - Returns: 可组合的目标 codepoint 列表。
  List<String> getCompatibleEmojiCodepoints(String emojiCodepoint) {
    return data[emojiCodepoint]?.combinations.keys.toList() ?? const [];
  }

  /// 获取两个 emoji 的最新组合图。
  ///
  /// - Parameters:
  ///   - leftEmojiCodepoint: 左侧 emoji codepoint。
  ///   - rightEmojiCodepoint: 右侧 emoji codepoint。
  /// - Returns: 最新组合结果；若无可用组合则返回 null。
  EmojiKitchenCombination? getLatestCombination(
    String leftEmojiCodepoint,
    String rightEmojiCodepoint,
  ) {
    final combinations = data[leftEmojiCodepoint]
        ?.combinations[rightEmojiCodepoint];
    if (combinations == null || combinations.isEmpty) {
      return null;
    }
    return combinations.firstWhere(
      (combination) => combination.isLatest,
      orElse: () => combinations.first,
    );
  }
}

/// 单个基础 emoji 的元数据。
class EmojiKitchenEmojiData {
  final String alt;
  final List<String> keywords;
  final String emojiCodepoint;
  final int gBoardOrder;
  final Map<String, List<EmojiKitchenCombination>> combinations;

  const EmojiKitchenEmojiData({
    required this.alt,
    required this.keywords,
    required this.emojiCodepoint,
    required this.gBoardOrder,
    required this.combinations,
  });

  /// 从 JSON 创建单个 emoji 数据对象。
  ///
  /// - Parameters:
  ///   - json: 元数据中的单个 emoji 节点。
  /// - Returns: 解析后的 emoji 数据对象。
  factory EmojiKitchenEmojiData.fromJson(Map<String, dynamic> json) {
    final rawCombinations = json['combinations'] as Map<String, dynamic>;
    return EmojiKitchenEmojiData(
      alt: json['alt'] as String,
      keywords: (json['keywords'] as List<dynamic>).cast<String>(),
      emojiCodepoint: json['emojiCodepoint'] as String,
      gBoardOrder: json['gBoardOrder'] as int,
      combinations: rawCombinations.map(
        (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map(
                (item) => EmojiKitchenCombination.fromJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

/// 单个 Emoji Kitchen 组合图信息。
class EmojiKitchenCombination {
  final String gStaticUrl;
  final String alt;
  final String leftEmoji;
  final String leftEmojiCodepoint;
  final String rightEmoji;
  final String rightEmojiCodepoint;
  final String date;
  final bool isLatest;
  final int gBoardOrder;

  const EmojiKitchenCombination({
    required this.gStaticUrl,
    required this.alt,
    required this.leftEmoji,
    required this.leftEmojiCodepoint,
    required this.rightEmoji,
    required this.rightEmojiCodepoint,
    required this.date,
    required this.isLatest,
    required this.gBoardOrder,
  });

  /// 从 JSON 创建组合图对象。
  ///
  /// - Parameters:
  ///   - json: 组合图 JSON 数据。
  /// - Returns: 解析后的组合图对象。
  factory EmojiKitchenCombination.fromJson(Map<String, dynamic> json) {
    return EmojiKitchenCombination(
      gStaticUrl: json['gStaticUrl'] as String,
      alt: json['alt'] as String,
      leftEmoji: json['leftEmoji'] as String,
      leftEmojiCodepoint: json['leftEmojiCodepoint'] as String,
      rightEmoji: json['rightEmoji'] as String,
      rightEmojiCodepoint: json['rightEmojiCodepoint'] as String,
      date: json['date'] as String,
      isLatest: json['isLatest'] as bool,
      gBoardOrder: json['gBoardOrder'] as int,
    );
  }
}

/// 界面展示用 Emoji 条目。
class EmojiKitchenCatalogEntry {
  final String emoji;
  final String emojiCodepoint;
  final String name;

  const EmojiKitchenCatalogEntry({
    required this.emoji,
    required this.emojiCodepoint,
    required this.name,
  });
}

final Map<String, EmojiKitchenCatalogEntry> _catalogByCodepoint = {
  for (final category in latestEmojiSet)
    for (final emoji in category.emoji)
      _emojiToCodepoint(emoji): EmojiKitchenCatalogEntry(
        emoji: emoji.emoji,
        emojiCodepoint: _emojiToCodepoint(emoji),
        name: emoji.name,
      ),
};

/// 把 emoji_picker_flutter 的 Emoji 对象转为 codepoint 字符串。
///
/// - Parameters:
///   - emoji: 需要转换的 emoji 对象。
/// - Returns: 以 `-` 拼接的小写十六进制 codepoint。
String _emojiToCodepoint(Emoji emoji) {
  return emoji.emoji.runes.map((rune) => rune.toRadixString(16)).join('-');
}

/// 根据 codepoint 还原展示用 emoji 字符。
///
/// - Parameters:
///   - emojiCodepoint: 需要还原的 codepoint。
/// - Returns: 对应的 emoji 字符串。
String _emojiFromCodepoint(String emojiCodepoint) {
  final codeUnits = emojiCodepoint
      .split('-')
      .map((part) => int.parse(part, radix: 16));
  return String.fromCharCodes(codeUnits);
}
