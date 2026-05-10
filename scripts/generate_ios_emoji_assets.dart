import 'dart:convert';
import 'dart:io';

const _variationSelector16 = 0xFE0F;

const _skinTones = <String>['🏻', '🏼', '🏽', '🏾', '🏿'];

const _defaultLatestEmojiSetPath = 'lib/utils/emoji/latest_emoji_set.dart';
const _defaultFontPath = 'assets/fonts/NotoColorEmoji.ttf';
const _defaultOutputDir = 'assets/generated/ios_emoji_webp';
const _defaultLookupOutput = 'lib/utils/emoji/generated_emoji_assets.dart';
const _defaultHbViewPath = 'hb-view';
const _defaultCwebpPath = 'cwebp';
const _defaultRenderSize = 160;
const _homebrewExecutableDirs = <String>['/opt/homebrew/bin', '/usr/local/bin'];

final _emojiLineRegex = RegExp(
  r"Emoji\('(.+?)', '.*?'(?:, hasSkinTone: (true|false))?\),",
);

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }

  final options = _parseArgs(args);
  if (options == null) return;

  final latestEmojiSetPath =
      options['--emoji-set'] ?? _defaultLatestEmojiSetPath;
  final fontPath = options['--font'] ?? _defaultFontPath;
  final outputDirPath = options['--output-dir'] ?? _defaultOutputDir;
  final lookupOutputPath = options['--lookup-output'] ?? _defaultLookupOutput;
  final requestedHbViewPath = options['--hb-view'] ?? _defaultHbViewPath;
  final requestedCwebpPath = options['--cwebp'] ?? _defaultCwebpPath;
  final renderSize =
      int.tryParse(options['--render-size'] ?? '$_defaultRenderSize') ??
      _defaultRenderSize;
  final forceRegenerate = options.containsKey('--force');

  final latestEmojiSetFile = File(latestEmojiSetPath);
  final fontFile = File(fontPath);
  final generatorFile = File(Platform.script.toFilePath());

  for (final file in [latestEmojiSetFile, fontFile, generatorFile]) {
    if (!file.existsSync()) {
      stderr.writeln('Required file not found: ${file.path}');
      exitCode = 66;
      return;
    }
  }

  final hbViewPath = _resolveExecutablePath(requestedHbViewPath);
  if (hbViewPath == null) {
    stderr.writeln(
      'Required command not found: $requestedHbViewPath. '
      'Install Homebrew formula "harfbuzz" or pass --hb-view <path>.',
    );
    exitCode = 69;
    return;
  }
  final cwebpPath = _resolveExecutablePath(requestedCwebpPath);
  if (cwebpPath == null) {
    stderr.writeln(
      'Required command not found: $requestedCwebpPath. '
      'Install Homebrew formula "webp" or pass --cwebp <path>.',
    );
    exitCode = 69;
    return;
  }

  final specs = _collectEmojiSpecs(latestEmojiSetFile.readAsStringSync());
  final outputDir = Directory(outputDirPath)..createSync(recursive: true);
  final lookupOutputFile = File(lookupOutputPath)
    ..parent.createSync(recursive: true);
  final stampFile = File('${outputDir.path}/.emoji_stamp.json');

  final expectedFileNames = {for (final spec in specs) spec.fileName};
  final fingerprint = jsonEncode({
    'emojiSetPath': latestEmojiSetPath,
    'emojiSetMtime': latestEmojiSetFile
        .statSync()
        .modified
        .millisecondsSinceEpoch,
    'emojiSetSize': latestEmojiSetFile.lengthSync(),
    'fontPath': fontPath,
    'fontMtime': fontFile.statSync().modified.millisecondsSinceEpoch,
    'fontSize': fontFile.lengthSync(),
    'hbViewPath': hbViewPath,
    'cwebpPath': cwebpPath,
    'generatorMtime': generatorFile.statSync().modified.millisecondsSinceEpoch,
    'generatorSize': generatorFile.lengthSync(),
    'renderSize': renderSize,
    'count': specs.length,
    'files': expectedFileNames.toList()..sort(),
  });

  final shouldSkip =
      !forceRegenerate &&
      stampFile.existsSync() &&
      lookupOutputFile.existsSync() &&
      stampFile.readAsStringSync() == fingerprint &&
      expectedFileNames.every(
        (name) => File('${outputDir.path}/$name').existsSync(),
      );

  if (shouldSkip) {
    stdout.writeln('iOS emoji assets are up to date (${specs.length} files).');
    return;
  }

  final staleFiles = outputDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.webp'))
      .where((file) => !expectedFileNames.contains(file.uri.pathSegments.last));
  for (final file in staleFiles) {
    file.deleteSync();
  }

  final tempDir = Directory.systemTemp.createTempSync('fluffychat-emoji-pngs.');
  try {
    for (final spec in specs) {
      final pngFile = File(
        '${tempDir.path}/${spec.fileName.replaceFirst('.webp', '.png')}',
      );
      final webpFile = File('${outputDir.path}/${spec.fileName}');

      final hbViewResult = await Process.run(hbViewPath, [
        '--font-size=$renderSize',
        '--font-funcs=ft',
        '--output-format=png',
        '--output-file=${pngFile.path}',
        '--background=none',
        '--margin=0',
        '--paint',
        fontPath,
        spec.emoji,
      ], workingDirectory: Directory.current.path);

      if (hbViewResult.exitCode != 0) {
        stdout.write(hbViewResult.stdout);
        stderr.write(hbViewResult.stderr);
        stderr.writeln('Failed to rasterize emoji: ${spec.emoji}');
        exitCode = hbViewResult.exitCode;
        return;
      }

      final cwebpResult = await Process.run(cwebpPath, [
        '-quiet',
        '-mt',
        '-q',
        '90',
        '-alpha_q',
        '100',
        pngFile.path,
        '-o',
        webpFile.path,
      ], workingDirectory: Directory.current.path);

      if (cwebpResult.exitCode != 0) {
        stdout.write(cwebpResult.stdout);
        stderr.write(cwebpResult.stderr);
        stderr.writeln('Failed to encode WebP for emoji: ${spec.emoji}');
        exitCode = cwebpResult.exitCode;
        return;
      }
    }
  } finally {
    tempDir.deleteSync(recursive: true);
  }

  lookupOutputFile.writeAsStringSync(_buildLookupDart(specs, outputDirPath));
  stampFile.writeAsStringSync(fingerprint);
  stdout.writeln(
    'Generated ${specs.length} iOS emoji assets into ${outputDir.path}',
  );
}

Map<String, String?>? _parseArgs(List<String> args) {
  final options = <String, String?>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--force') {
      options[arg] = null;
      continue;
    }
    if (!arg.startsWith('--')) {
      stderr.writeln('Unexpected argument: $arg');
      exitCode = 64;
      return null;
    }
    if (i + 1 >= args.length) {
      stderr.writeln('Missing value for $arg');
      exitCode = 64;
      return null;
    }
    options[arg] = args[++i];
  }
  return options;
}

List<_EmojiAssetSpec> _collectEmojiSpecs(String source) {
  final specsByCanonicalEmoji = <String, _EmojiAssetSpec>{};
  for (final match in _emojiLineRegex.allMatches(source)) {
    final emoji = match.group(1)!;
    final hasSkinTone = match.group(2) == 'true';
    _addSpec(specsByCanonicalEmoji, emoji);
    if (hasSkinTone) {
      for (final skinTone in _skinTones) {
        _addSpec(specsByCanonicalEmoji, _applySkinTone(emoji, skinTone));
      }
    }
  }
  final specs = specsByCanonicalEmoji.values.toList()
    ..sort((a, b) => a.fileName.compareTo(b.fileName));
  return specs;
}

void _addSpec(
  Map<String, _EmojiAssetSpec> specsByCanonicalEmoji,
  String emoji,
) {
  final canonicalEmoji = _canonicalizeEmojiAssetKey(emoji);
  specsByCanonicalEmoji.putIfAbsent(
    canonicalEmoji,
    () => _EmojiAssetSpec(
      emoji: emoji,
      canonicalEmoji: canonicalEmoji,
      fileName: '${_emojiFileStem(canonicalEmoji)}.webp',
    ),
  );
}

String _applySkinTone(String emoji, String skinTone) {
  final codeUnits = emoji.codeUnits;
  final result = <int>[
    ...codeUnits.sublist(0, codeUnits.length >= 2 ? 2 : codeUnits.length),
    ...skinTone.codeUnits,
    if (codeUnits.length >= 2) ...codeUnits.sublist(2),
  ];
  return String.fromCharCodes(result);
}

String _canonicalizeEmojiAssetKey(String value) {
  final filteredRunes = <int>[];
  for (final rune in value.runes) {
    if (rune == _variationSelector16) continue;
    filteredRunes.add(rune);
  }
  return String.fromCharCodes(filteredRunes);
}

String _emojiFileStem(String value) => value.runes
    .map((rune) => rune.toRadixString(16).toUpperCase().padLeft(4, '0'))
    .join('-');

String _buildLookupDart(List<_EmojiAssetSpec> specs, String outputDirPath) {
  final escapedBasePath = _escapeDartString(outputDirPath);
  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT.')
    ..writeln('// Run: dart run scripts/generate_ios_emoji_assets.dart')
    ..writeln()
    ..writeln(
      "const String kGeneratedIosEmojiAssetBasePath = '$escapedBasePath';",
    )
    ..writeln()
    ..writeln('const Set<String> kGeneratedIosEmojiAssetLookupKeys = {');

  for (final spec in specs) {
    buffer.writeln("  '${_escapeDartString(spec.canonicalEmoji)}',");
  }

  buffer
    ..writeln('};')
    ..writeln();

  return buffer.toString();
}

String _escapeDartString(String value) {
  return value.replaceAll('\\', '\\\\').replaceAll("'", r"\'");
}

bool _commandExists(String command) {
  final result = Process.runSync('/usr/bin/which', [command]);
  return result.exitCode == 0;
}

String? _resolveExecutablePath(String command) {
  if (_looksLikePath(command)) {
    return File(command).existsSync() ? command : null;
  }
  if (_commandExists(command)) {
    return command;
  }
  for (final candidate in _homebrewExecutableDirs) {
    final resolved = File('$candidate/$command');
    if (resolved.existsSync()) {
      return resolved.path;
    }
  }
  return null;
}

bool _looksLikePath(String value) {
  return value.contains(Platform.pathSeparator) || value.startsWith('.');
}

const _usage = '''
Usage: dart run scripts/generate_ios_emoji_assets.dart [options]

Options:
  --emoji-set <path>       Input emoji set dart file.
  --font <path>            Emoji font file to rasterize.
  --output-dir <path>      Output directory for generated webp assets.
  --lookup-output <path>   Output dart lookup file.
  --hb-view <path>         hb-view binary path.
  --cwebp <path>           cwebp binary path.
  --render-size <int>      Approximate font render size in px. Default: 160.
  --force                  Ignore the cached stamp and regenerate everything.
''';

class _EmojiAssetSpec {
  const _EmojiAssetSpec({
    required this.emoji,
    required this.canonicalEmoji,
    required this.fileName,
  });

  final String emoji;
  final String canonicalEmoji;
  final String fileName;
}
