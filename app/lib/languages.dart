import 'dart:ui' show PlatformDispatcher;

/// Languages the app offers for the user's own language and for transcription, each in its own script.
/// whisperX recognizes all of them, and its alignment step (speaker labels) has a model for each.
const userLanguages = <(String, String)>[
  ('ko', '한국어'),
  ('en', 'English'),
  ('ja', '日本語'),
  ('zh', '中文'),
  ('es', 'Español'),
  ('fr', 'Français'),
  ('de', 'Deutsch'),
  ('pt', 'Português'),
  ('vi', 'Tiếng Việt'),
  ('ru', 'Русский'),
];

String languageName(String code) => userLanguages.where((l) => l.$1 == code).firstOrNull?.$2 ?? code;

/// The system's language when the app offers it, else Korean (the app's own language).
String systemLanguage() {
  final code = PlatformDispatcher.instance.locale.languageCode;
  return userLanguages.any((l) => l.$1 == code) ? code : 'ko';
}
