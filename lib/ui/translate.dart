import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'theme.dart';

/// Android and ML Kit don't always agree on a language's code.
const _codeAliases = {'iw': 'he', 'in': 'id', 'nb': 'no', 'nn': 'no'};

/// The ML Kit language for a BCP-47 tag such as `ja` or `pt-BR`, or null
/// when it can't be translated (including ML Kit's `und` and romanized tags
/// like `ja-Latn`).
TranslateLanguage? translateLanguageOf(String tag) {
  final parts = tag.toLowerCase().split(RegExp('[-_]'));
  if (parts.length > 1 && parts[1] == 'latn') return null;
  final code = _codeAliases[parts.first] ?? parts.first;
  for (final language in TranslateLanguage.values) {
    if (language.bcpCode == code) return language;
  }
  return null;
}

/// The system language when ML Kit can translate into it, otherwise English.
TranslateLanguage translationTarget(Locale locale) =>
    translateLanguageOf(locale.languageCode) ?? TranslateLanguage.english;

/// The language's English name, such as Japanese.
String languageName(TranslateLanguage language) {
  final name = language.name;
  return name[0].toUpperCase() + name.substring(1);
}

/// Text split into the lines it's translated by, so paragraphs and blank
/// lines come back where they were.
List<String> translationLines(String text) => text.split('\n');

/// A post's title and text in another language.
class Translation {
  const Translation({
    required this.from,
    required this.to,
    required this.title,
    required this.text,
  });

  final TranslateLanguage from;
  final TranslateLanguage to;
  final String title;
  final String text;
}

/// Offline translation with ML Kit: the language is identified by a model
/// shipped in the app, and the text translated with language packs (about
/// 30 MB each) downloaded once, so post text never leaves the device.
/// Results are kept for the session by post key.
class PostTranslator {
  PostTranslator._();

  static final instance = PostTranslator._();

  /// Lower than ML Kit's default 0.5: post text is short and mixed.
  final _identifier = LanguageIdentifier(confidenceThreshold: .4);
  final _packs = OnDeviceTranslatorModelManager();
  final _detected = <String, Future<TranslateLanguage?>>{};
  final _done = <String, Translation>{};

  TranslateLanguage get target =>
      translationTarget(PlatformDispatcher.instance.locale);

  Translation? cached(String key) {
    final done = _done[key];
    return done != null && done.to == target ? done : null;
  }

  /// The post's language when it differs from [target] and can be
  /// translated; null otherwise, or when it can't be told.
  Future<TranslateLanguage?> detect(String key, String text) =>
      _detected[key] ??= _identify(text);

  Future<TranslateLanguage?> _identify(String text) async {
    // The first few lines are enough and keep the call quick.
    final sample = text.length > 600 ? text.substring(0, 600) : text;
    if (sample.trim().length < 4) return null;
    try {
      final tag = await _identifier.identifyLanguage(sample);
      final language = translateLanguageOf(tag);
      return language == target ? null : language;
    } catch (_) {
      return null;
    }
  }

  /// The language packs [from] and [target] need that aren't on the device.
  Future<List<TranslateLanguage>> missingPacks(TranslateLanguage from) async {
    final missing = <TranslateLanguage>[];
    for (final language in {from, target}) {
      if (!await _packs.isModelDownloaded(language.bcpCode)) {
        missing.add(language);
      }
    }
    return missing;
  }

  Future<void> download(List<TranslateLanguage> packs) async {
    for (final language in packs) {
      final ok = await _packs.downloadModel(
        language.bcpCode,
        isWifiRequired: false,
      );
      if (!ok) throw StateError('Could not download ${languageName(language)}');
    }
  }

  Future<Translation> translate(
    String key,
    TranslateLanguage from, {
    required String title,
    required String text,
  }) async {
    final to = target;
    final translator = OnDeviceTranslator(
      sourceLanguage: from,
      targetLanguage: to,
    );
    Future<String> lines(String text) async {
      final out = <String>[];
      for (final line in translationLines(text)) {
        out.add(
          line.trim().isEmpty ? line : await translator.translateText(line),
        );
      }
      return out.join('\n');
    }

    try {
      final translation = Translation(
        from: from,
        to: to,
        title: title.isEmpty ? '' : await lines(title),
        text: await lines(text),
      );
      return _done[key] = translation;
    } finally {
      await translator.close();
    }
  }
}

/// Under a post's text: "Translate from Japanese" when the post isn't in the
/// system language, then the translation with a way back to the original.
class TranslatePost extends StatefulWidget {
  const TranslatePost({
    super.key,
    required this.postKey,
    required this.title,
    required this.text,
  });

  final String postKey;
  final String title;

  /// The post's plain text.
  final String text;

  @override
  State<TranslatePost> createState() => _TranslatePostState();
}

class _TranslatePostState extends State<TranslatePost> {
  final _translator = PostTranslator.instance;
  TranslateLanguage? _from;
  Translation? _translation;
  bool _shown = false;

  /// What's happening while busy, such as "Translating…".
  String? _busy;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void didUpdateWidget(TranslatePost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postKey != widget.postKey) {
      _from = null;
      _translation = null;
      _shown = false;
      _busy = null;
      _detect();
    }
  }

  Future<void> _detect() async {
    final key = widget.postKey;
    final cached = _translator.cached(key);
    if (cached != null) {
      setState(() {
        _from = cached.from;
        _translation = cached;
        _shown = true;
      });
      return;
    }
    final from = await _translator.detect(
      key,
      [widget.title, widget.text].where((t) => t.isNotEmpty).join('\n'),
    );
    if (mounted && key == widget.postKey) setState(() => _from = from);
  }

  Future<void> _translate() async {
    final from = _from;
    if (from == null || _busy != null) return;
    if (_translation != null) {
      setState(() => _shown = true);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final key = widget.postKey;
    try {
      final missing = await _translator.missingPacks(from);
      if (missing.isNotEmpty) {
        if (!mounted || !await _askDownload(missing)) return;
        setState(() => _busy = 'Downloading language pack…');
        await _translator.download(missing);
      }
      if (!mounted) return;
      setState(() => _busy = 'Translating…');
      final translation = await _translator.translate(
        key,
        from,
        title: widget.title,
        text: widget.text,
      );
      if (mounted && key == widget.postKey) {
        setState(() {
          _translation = translation;
          _shown = true;
        });
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not translate this post')),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<bool> _askDownload(List<TranslateLanguage> packs) async {
    final names = packs.map(languageName).join(' and ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Download language pack?'),
        content: Text(
          'Translating needs the $names language '
          '${packs.length == 1 ? 'pack' : 'packs'} (about 30 MB each). '
          'After that, posts are translated on this device, offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final from = _from;
    if (from == null) return const SizedBox.shrink();
    final translation = _translation;
    final busy = _busy;
    final link = TextStyle(color: pinkText, fontWeight: FontWeight.w600);
    if (busy != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: pinkText),
            ),
            const SizedBox(width: 10),
            Text(busy, style: TextStyle(color: ink(.6))),
          ],
        ),
      );
    }
    if (translation == null || !_shown) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _translate,
          icon: Icon(Icons.translate_rounded, size: 18, color: pinkText),
          label: Text('Translate from ${languageName(from)}', style: link),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: pinkText, width: 2)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.translate_rounded, size: 15, color: ink(.5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Translated from ${languageName(translation.from)} '
                      'on this device',
                      style: TextStyle(color: ink(.5), fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _shown = false),
                    child: Text('Hide', style: link.copyWith(fontSize: 13)),
                  ),
                ],
              ),
              if (translation.title.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  translation.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
              if (translation.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  translation.text.trim(),
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
