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
};

String normalizeLanguage(String? raw) {
  var v = (raw ?? '').trim().toLowerCase();
  if (v.isEmpty || v == 'und' || v == 'unknown' || v == 'zxx' || v == 'mis') return '';
  v = v.split(RegExp(r'[-_]')).first.replaceAll(RegExp('[^a-z]'), '');
  if (v.isEmpty) return '';
  if (v.length == 2) return v;
  return _iso3To1[v] ?? _englishNames[v] ?? v;
}

const Map<String, String> _iso3To1 = {
  'eng': 'en', 'ron': 'ro', 'rum': 'ro', 'fre': 'fr', 'fra': 'fr', 'ger': 'de', 'deu': 'de',
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
};
