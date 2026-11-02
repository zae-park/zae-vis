// What a line typed in the chat wants: hits (검색), an answer written from them (질문), or a file (내려받기).
// Rules, not a model: a second agent call just to route would add seconds to every line.

enum ChatIntent { search, ask, download }

/// Words that always mean "give me the file".
final _downloadStrong = RegExp(r'다운(?!타임|그레이드)|내려\s*받|내보내|export|download', caseSensitive: false);

/// Words that mean it unless the line is a question ("txt로 저장하는 방법은?").
final _downloadWeak = RegExp(r'(txt|md|텍스트|마크다운)\s*(파일)?\s*(로|으로)|파일\s*(로|을|를)?\s*(줘|주세요|줄래|받|보내)|저장\s*(해|하고|할래|해줘)', caseSensitive: false);

final _questionWord = RegExp(r'왜|어떻게|무엇|뭐|뭘|언제|어디|누가|누구|어떤|얼마|몇\s|알려|설명|요약|정리해|비교|차이|이유|했지|였지|했나|됐지|인가|인지|할까|나요|까요|있어\?|없어\?');

/// A sentence ending ("미뤘다", "막혔어요") rather than a list of keywords.
final _sentenceEnd = RegExp(r'[다요지까죠야어니나냐]$');

ChatIntent chatIntent(String text) {
  final t = text.trim();
  final asks = t.endsWith('?') || t.endsWith('？');
  if (_downloadStrong.hasMatch(t)) return ChatIntent.download;
  if (!asks && _downloadWeak.hasMatch(t)) return ChatIntent.download;
  if (asks || _questionWord.hasMatch(t)) return ChatIntent.ask;
  if (t.length >= 8 && t.contains(' ') && _sentenceEnd.hasMatch(t)) return ChatIntent.ask;
  return ChatIntent.search;
}

/// "[2]" or "2번" in a line: the earlier source or hit it points at.
int? citedNumber(String text) {
  final m = RegExp(r'\[(\d+)\]|(?<!\d)(\d+)\s*번').firstMatch(text);
  final s = m?.group(1) ?? m?.group(2);
  return s == null ? null : int.tryParse(s);
}

/// "이거", "그 파일", "방금 것": the line points back at what the chat just showed.
bool pointsBack(String text) => RegExp(r'이거|그거|이것|그것|이\s*파일|그\s*파일|방금|위\s*(의|에)?\s*(파일|것|거)|여기\s*(나온|있는)|이\s*원문|그\s*원문').hasMatch(text);
