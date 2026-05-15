import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'emoji_kitchen_service.dart';

/// Mixed reaction 处理结果。
class EmojiKitchenReactionResult {
  final Uri mxc;
  final bool reusedExisting;

  const EmojiKitchenReactionResult({
    required this.mxc,
    required this.reusedExisting,
  });
}

/// 负责把 Emoji Kitchen 组合图转换为可复用的 Matrix reaction 资源。
class EmojiKitchenReactionService {
  static const String _userEmotesEventType = 'im.ponies.user_emotes';

  /// 发送 mixed emoji reaction。
  ///
  /// - Parameters:
  ///   - context: 当前界面上下文，用于提示和本地化。
  ///   - event: 需要被回应的消息事件。
  ///   - combination: 当前选中的 Emoji Kitchen 组合图信息。
  /// - Returns: 成功发送的 reaction key（mxc）。
  /// - Throws: 当图片下载、上传、保存 image pack 或发送 reaction 失败时抛出异常。
  static Future<String> sendMixedReaction({
    required BuildContext context,
    required Event event,
    required EmojiKitchenCombination combination,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);

    scaffoldMessenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(minutes: 5),
          dismissDirection: DismissDirection.none,
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text(l10n.sendingAttachment),
            ],
          ),
        ),
      );

    try {
      final result = await ensureReactionMxc(
        room: event.room,
        combination: combination,
      );
      await event.room.sendReaction(event.eventId, result.mxc.toString());
      scaffoldMessenger.clearSnackBars();
      return result.mxc.toString();
    } catch (error, stackTrace) {
      Logs().e('Unable to send mixed emoji reaction', error, stackTrace);
      scaffoldMessenger.clearSnackBars();
      if (!context.mounted) {
        rethrow;
      }
      final theme = Theme.of(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          closeIconColor: theme.colorScheme.onErrorContainer,
          content: Text(
            error.toLocalizedString(context),
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          duration: const Duration(seconds: 30),
          showCloseIcon: true,
        ),
      );
      rethrow;
    }
  }

  /// 确保 mixed emoji 已存在于可复用的 image pack 中。
  ///
  /// - Parameters:
  ///   - room: 当前聊天房间，用于读取已激活的 image packs。
  ///   - combination: 当前选中的 Emoji Kitchen 组合图信息。
  /// - Returns: mixed emoji 对应的 mxc 及是否复用了现有资源。
  /// - Throws: 当网络下载、媒体上传或账户数据保存失败时抛出异常。
  static Future<EmojiKitchenReactionResult> ensureReactionMxc({
    required Room room,
    required EmojiKitchenCombination combination,
  }) async {
    final imageCode = buildImageCode(combination);
    final existingMxc = _findExistingMxc(room: room, imageCode: imageCode);
    if (existingMxc != null) {
      return EmojiKitchenReactionResult(
        mxc: existingMxc,
        reusedExisting: true,
      );
    }

    final uploadedImage = await _downloadMixedImage(combination);
    final uploadedMxc = await room.client.uploadContent(
      uploadedImage.bytes,
      filename: uploadedImage.name,
      contentType: uploadedImage.mimeType,
    );

    final userPackEvent =
        room.client.accountData[_userEmotesEventType] ??
        BasicEvent(type: 'm.dummy', content: {});
    final userPack = BasicEvent.fromJson(
      userPackEvent.toJson(),
    ).parsedImagePackContent;
    userPack.images[imageCode] = ImagePackImageContent(
      url: uploadedMxc,
      body: combination.alt,
      info: _normalizeStickerInfo(uploadedImage.info),
      usage: const [ImagePackUsage.sticker, ImagePackUsage.emoticon],
    );

    await room.client.setAccountData(
      room.client.userID!,
      _userEmotesEventType,
      userPack.toJson(),
    );

    return EmojiKitchenReactionResult(
      mxc: uploadedMxc,
      reusedExisting: false,
    );
  }

  /// 根据 mixed 组合名称生成固定 shortcode。
  ///
  /// - Parameters:
  ///   - combination: 当前选中的 Emoji Kitchen 组合图信息。
  /// - Returns: 可用于 image pack 的 shortcode。
  static String buildImageCode(EmojiKitchenCombination combination) {
    return EmojiKitchenService.buildFileName(combination.alt).replaceFirst(
      RegExp(r'\.png$'),
      '',
    );
  }

  /// 在当前房间可用的 image pack 中查找已存在的 mixed emoji。
  ///
  /// - Parameters:
  ///   - room: 当前聊天房间。
  ///   - imageCode: 目标 mixed emoji 的 shortcode。
  /// - Returns: 若存在则返回对应 mxc，否则返回 null。
  static Uri? _findExistingMxc({
    required Room room,
    required String imageCode,
  }) {
    final activeImagePacks = room.getImagePacks();
    for (final pack in activeImagePacks.values) {
      final image = pack.images[imageCode];
      if (image != null) {
        return image.url;
      }
    }
    return null;
  }

  /// 下载并规范化 mixed emoji 图片，确保它适合 sticker/image pack 复用。
  ///
  /// - Parameters:
  ///   - combination: 当前选中的 Emoji Kitchen 组合图信息。
  /// - Returns: 上传前的图片文件对象。
  /// - Throws: 当远端下载失败时抛出异常。
  static Future<MatrixImageFile> _downloadMixedImage(
    EmojiKitchenCombination combination,
  ) async {
    final response = await http.get(Uri.parse(combination.gStaticUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to download Emoji Kitchen image: ${response.statusCode}',
      );
    }

    var file = MatrixImageFile(
      bytes: response.bodyBytes,
      name: EmojiKitchenService.buildFileName(combination.alt),
      mimeType: 'image/png',
    );

    file =
        await file.generateThumbnail(
          nativeImplementations: ClientManager.nativeImplementations,
        ) ??
        file;
    return file;
  }

  /// 规范 sticker 尺寸信息，保持与现有 custom emoji/sticker 导入逻辑一致。
  ///
  /// - Parameters:
  ///   - sourceInfo: 原始图片信息。
  /// - Returns: 归一化后的图片信息。
  static Map<String, Object?> _normalizeStickerInfo(
    Map<String, Object?> sourceInfo,
  ) {
    final normalizedInfo = <String, Object?>{...sourceInfo};
    if (normalizedInfo['w'] is! int || normalizedInfo['h'] is! int) {
      return normalizedInfo;
    }

    final width = normalizedInfo['w'] as int;
    final height = normalizedInfo['h'] as int;
    if (width <= 0 || height <= 0) {
      return normalizedInfo;
    }

    final ratio = width / height;
    if (width > height) {
      normalizedInfo['w'] = 256;
      normalizedInfo['h'] = (256.0 / ratio).round();
      return normalizedInfo;
    }

    normalizedInfo['h'] = 256;
    normalizedInfo['w'] = (ratio * 256.0).round();
    return normalizedInfo;
  }
}
