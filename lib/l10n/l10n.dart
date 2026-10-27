import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';
export 'problems.dart';

extension L10nContext on BuildContext {
  L10n get l10n => L10n.of(this);
}
