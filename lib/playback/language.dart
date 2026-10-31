library;

const languageNames = {
  'en': 'English',
  'ro': 'Română',
  'fr': 'Français',
  'de': 'Deutsch',
  'es': 'Español',
  'it': 'Italiano',
  'pt': 'Português',
  'hu': 'Magyar',
  'ja': '日本語',
  'ko': '한국어',
  'pl': 'Polski',
  'nl': 'Nederlands',
  'sv': 'Svenska',
  'da': 'Dansk',
  'no': 'Norsk',
  'fi': 'Suomi',
  'cs': 'Čeština',
  'sk': 'Slovenčina',
  'sl': 'Slovenščina',
  'hr': 'Hrvatski',
  'sr': 'Srpski',
  'bs': 'Bosanski',
  'bg': 'Български',
  'mk': 'Македонски',
  'sq': 'Shqip',
  'el': 'Ελληνικά',
  'tr': 'Türkçe',
  'ru': 'Русский',
  'uk': 'Українська',
  'et': 'Eesti',
  'lv': 'Latviešu',
  'lt': 'Lietuvių',
  'is': 'Íslenska',
  'ca': 'Català',
  'eu': 'Euskara',
  'gl': 'Galego',
  'ar': 'العربية',
  'he': 'עברית',
  'fa': 'فارسی',
  'hi': 'हिन्दी',
  'bn': 'বাংলা',
  'ta': 'தமிழ்',
  'te': 'తెలుగు',
  'ur': 'اردو',
  'zh': '中文',
  'vi': 'Tiếng Việt',
  'th': 'ไทย',
  'id': 'Bahasa Indonesia',
  'ms': 'Bahasa Melayu',
  'tl': 'Filipino',
};

String normalizeLanguage(String? raw) {
  var v = (raw ?? '').trim().toLowerCase();
  if (v.isEmpty || v == 'und' || v == 'unknown' || v == 'zxx' || v == 'mis') return '';
  v = v.split(RegExp(r'[-_]')).first.replaceAll(RegExp('[^a-z]'), '');
  if (v.isEmpty) return '';
  if (v.length == 2) return v;
  return _iso3To1[v] ?? _englishNames[v] ?? v;
}

String? searchLanguageCode(String iso1) {
  for (final e in _iso3To1.entries) {
    if (e.value == iso1) return e.key;
  }
  return null;
}

const Map<String, String> _iso3To1 = {
  'eng': 'en', 'rum': 'ro', 'ron': 'ro', 'fre': 'fr', 'fra': 'fr', 'ger': 'de', 'deu': 'de',
  'spa': 'es', 'ita': 'it', 'por': 'pt', 'jpn': 'ja', 'chi': 'zh', 'zho': 'zh', 'kor': 'ko',
  'dut': 'nl', 'nld': 'nl', 'nor': 'no', 'nob': 'nb', 'nno': 'nn', 'dan': 'da', 'fin': 'fi',
  'swe': 'sv', 'pol': 'pl', 'rus': 'ru', 'ukr': 'uk', 'cze': 'cs', 'ces': 'cs', 'slo': 'sk',
  'slk': 'sk', 'slv': 'sl', 'hun': 'hu', 'gre': 'el', 'ell': 'el', 'tur': 'tr', 'ara': 'ar',
  'heb': 'he', 'hin': 'hi', 'tha': 'th', 'vie': 'vi', 'ind': 'id', 'may': 'ms', 'msa': 'ms',
  'bul': 'bg', 'hrv': 'hr', 'srp': 'sr', 'bos': 'bs', 'mac': 'mk', 'mkd': 'mk', 'alb': 'sq',
  'sqi': 'sq', 'est': 'et', 'lav': 'lv', 'lit': 'lt', 'ice': 'is', 'isl': 'is', 'per': 'fa',
  'fas': 'fa', 'cat': 'ca', 'baq': 'eu', 'eus': 'eu', 'glg': 'gl', 'wel': 'cy', 'cym': 'cy',
  'gle': 'ga', 'tam': 'ta', 'tel': 'te', 'ben': 'bn', 'urd': 'ur', 'fil': 'tl', 'tgl': 'tl',
  'geo': 'ka', 'kat': 'ka', 'arm': 'hy', 'hye': 'hy', 'aze': 'az', 'kaz': 'kk', 'mol': 'ro',
};

const Map<String, String> _englishNames = {
  'english': 'en', 'romanian': 'ro', 'french': 'fr', 'german': 'de', 'spanish': 'es',
  'italian': 'it', 'portuguese': 'pt', 'japanese': 'ja', 'chinese': 'zh', 'korean': 'ko',
  'dutch': 'nl', 'norwegian': 'no', 'danish': 'da', 'finnish': 'fi', 'swedish': 'sv',
  'polish': 'pl', 'russian': 'ru', 'ukrainian': 'uk', 'czech': 'cs', 'hungarian': 'hu',
  'greek': 'el', 'turkish': 'tr', 'arabic': 'ar', 'hebrew': 'he', 'hindi': 'hi',
  'vietnamese': 'vi', 'thai': 'th', 'indonesian': 'id', 'malay': 'ms', 'bulgarian': 'bg',
  'croatian': 'hr', 'serbian': 'sr', 'bosnian': 'bs', 'slovak': 'sk', 'slovenian': 'sl',
  'estonian': 'et', 'latvian': 'lv', 'lithuanian': 'lt', 'icelandic': 'is', 'persian': 'fa',
  'catalan': 'ca', 'basque': 'eu', 'galician': 'gl', 'macedonian': 'mk', 'albanian': 'sq',
  'bengali': 'bn', 'tamil': 'ta', 'telugu': 'te', 'urdu': 'ur', 'filipino': 'tl',
};
