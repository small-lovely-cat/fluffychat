import 'dart:io';

enum _EmojiCategory {
  smileys,
  animals,
  foods,
  activities,
  travel,
  objects,
  symbols,
  flags,
}

class _EmojiEntry {
  const _EmojiEntry(this.emoji, this.name, {this.hasSkinTone = false});

  final String emoji;
  final String name;
  final bool hasSkinTone;

  _EmojiEntry copyWith({bool? hasSkinTone}) =>
      _EmojiEntry(emoji, name, hasSkinTone: hasSkinTone ?? this.hasSkinTone);
}

const _emojiLinePattern =
    r'^\s*([0-9A-F ]+)\s*;\s*([a-z-]+)\s*#\s*(\S+)\s+E([0-9.]+)\s+(.+?)\s*$';
final _emojiLineRegex = RegExp(_emojiLinePattern);
final _skinToneRegex = RegExp(r'[\u{1F3FB}-\u{1F3FF}]', unicode: true);

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run scripts/generate_latest_emoji_set.dart <emoji-test.txt> [output.dart]',
    );
    exit(64);
  }

  final inputPath = args[0];
  final outputPath = args.length == 2
      ? args[1]
      : 'lib/utils/emoji/latest_emoji_set.dart';

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('Input file not found: $inputPath');
    exit(66);
  }

  final lines = inputFile.readAsLinesSync();

  final entriesByCategory = <_EmojiCategory, Map<String, _EmojiEntry>>{
    for (final category in _EmojiCategory.values)
      category: <String, _EmojiEntry>{},
  };
  final skinToneBaseEmoji = <String>{};

  var currentGroup = 'Objects';
  String? unicodeVersion;

  for (final line in lines) {
    final trimmed = line.trim();

    if (trimmed.startsWith('# Version:')) {
      unicodeVersion = trimmed.substring('# Version:'.length).trim();
      continue;
    }

    if (trimmed.startsWith('# group:')) {
      currentGroup = trimmed.substring('# group:'.length).trim();
      continue;
    }

    final match = _emojiLineRegex.firstMatch(line);
    if (match == null) {
      continue;
    }

    final status = match.group(2)!;
    if (status != 'fully-qualified') {
      continue;
    }

    final emoji = match.group(3)!;
    final name = match.group(5)!;

    final baseEmoji = emoji.replaceAll(_skinToneRegex, '');
    final isSkinToneVariant =
        baseEmoji != emoji || name.toLowerCase().contains('skin tone');

    if (isSkinToneVariant) {
      skinToneBaseEmoji.add(baseEmoji);
      continue;
    }

    final category = _mapGroupToCategory(currentGroup);
    final categoryEntries = entriesByCategory[category]!;
    categoryEntries.putIfAbsent(baseEmoji, () => _EmojiEntry(baseEmoji, name));
  }

  for (final category in entriesByCategory.keys) {
    final updated = <String, _EmojiEntry>{};
    for (final entry in entriesByCategory[category]!.entries) {
      updated[entry.key] = entry.value.copyWith(
        hasSkinTone: skinToneBaseEmoji.contains(entry.key),
      );
    }
    entriesByCategory[category] = updated;
  }

  final output = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT.')
    ..writeln(
      '// Source: https://www.unicode.org/Public/emoji/latest/emoji-test.txt',
    )
    ..writeln('// Unicode Emoji Version: ${unicodeVersion ?? 'unknown'}')
    ..writeln()
    ..writeln(
      "import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';",
    )
    ..writeln()
    ..writeln('const List<CategoryEmoji> latestEmojiSet = [');

  for (final category in _EmojiCategory.values) {
    final entries = entriesByCategory[category]!.values;
    output.writeln('  CategoryEmoji(${_dartCategory(category)}, [');
    for (final entry in entries) {
      final escapedName = _escapeDartString(entry.name);
      if (entry.hasSkinTone) {
        output.writeln(
          "    Emoji('${entry.emoji}', '$escapedName', hasSkinTone: true),",
        );
      } else {
        output.writeln("    Emoji('${entry.emoji}', '$escapedName'),");
      }
    }
    output.writeln('  ]),');
  }

  output.writeln('];');

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(output.toString());

  stdout.writeln('Generated $outputPath');
  stdout.writeln(
    'Entries: ${entriesByCategory.values.fold<int>(0, (n, map) => n + map.length)}',
  );
}

_EmojiCategory _mapGroupToCategory(String group) {
  switch (group) {
    case 'Smileys & Emotion':
    case 'People & Body':
    case 'Component':
      return _EmojiCategory.smileys;
    case 'Animals & Nature':
      return _EmojiCategory.animals;
    case 'Food & Drink':
      return _EmojiCategory.foods;
    case 'Activities':
      return _EmojiCategory.activities;
    case 'Travel & Places':
      return _EmojiCategory.travel;
    case 'Objects':
      return _EmojiCategory.objects;
    case 'Symbols':
      return _EmojiCategory.symbols;
    case 'Flags':
      return _EmojiCategory.flags;
    default:
      return _EmojiCategory.objects;
  }
}

String _dartCategory(_EmojiCategory category) {
  switch (category) {
    case _EmojiCategory.smileys:
      return 'Category.SMILEYS';
    case _EmojiCategory.animals:
      return 'Category.ANIMALS';
    case _EmojiCategory.foods:
      return 'Category.FOODS';
    case _EmojiCategory.activities:
      return 'Category.ACTIVITIES';
    case _EmojiCategory.travel:
      return 'Category.TRAVEL';
    case _EmojiCategory.objects:
      return 'Category.OBJECTS';
    case _EmojiCategory.symbols:
      return 'Category.SYMBOLS';
    case _EmojiCategory.flags:
      return 'Category.FLAGS';
  }
}

String _escapeDartString(String value) {
  return value.replaceAll(r'\\', r'\\\\').replaceAll("'", r"\\'");
}
