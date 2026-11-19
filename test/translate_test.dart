import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:pawress/ui/translate.dart';

void main() {
  test('language tags map to ML Kit languages', () {
    expect(translateLanguageOf('ja'), TranslateLanguage.japanese);
    expect(translateLanguageOf('pt-BR'), TranslateLanguage.portuguese);
    expect(translateLanguageOf('zh_TW'), TranslateLanguage.chinese);
    expect(translateLanguageOf('iw'), TranslateLanguage.hebrew);
    expect(translateLanguageOf('in'), TranslateLanguage.indonesian);
    expect(translateLanguageOf('nb'), TranslateLanguage.norwegian);
    expect(translateLanguageOf('und'), isNull);
    expect(translateLanguageOf('ja-Latn'), isNull);
  });

  test('translations go to the system language, else English', () {
    expect(
      translationTarget(const Locale('es', 'MX')),
      TranslateLanguage.spanish,
    );
    expect(translationTarget(const Locale('en')), TranslateLanguage.english);
    expect(translationTarget(const Locale('xx')), TranslateLanguage.english);
  });

  test('language names and lines', () {
    expect(languageName(TranslateLanguage.japanese), 'Japanese');
    expect(translationLines('a\n\nb'), ['a', '', 'b']);
  });
}
