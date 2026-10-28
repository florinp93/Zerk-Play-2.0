import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../l10n/l10n.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/media_row.dart';
import '../widgets/setting_rows.dart';

class HomeCollectionsPage extends StatefulWidget {
  const HomeCollectionsPage({super.key});

  @override
  State<HomeCollectionsPage> createState() => _HomeCollectionsPageState();
}

class _HomeCollectionsPageState extends State<HomeCollectionsPage> {
  late final AppServices _services = AppServicesScope.read(context);
  late final String _userId = _services.janus.session.userId;
  late List<(String, String)> _picked = [..._services.settings.homeCollectionsOf(_userId)];
  late final Future<List<EmbyItem>> _all = _services.catalog.boxSets();

  void _save(List<(String, String)> next) {
    setState(() => _picked = next);
    _services.updateSettings(_services.settings.withHomeCollections(_userId, next));
  }

  void _moveUp(int i) => _save([..._picked]..insert(i - 1, _picked.removeAt(i)));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(left: contentLeft, top: 90, right: 120),
      child: SizedBox(
        width: 1100,
        child: FutureBuilder<List<EmbyItem>>(
          future: _all,
          builder: (context, snap) {
            final all = snap.data;
            final picked = {for (final (id, _) in _picked) id};
            return FocusZone(
              debugLabel: 'settings-home-collections',
              autofocus: true,
              child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
                Text(l10n.homeCollections, style: Zt.headline),
                const SizedBox(height: 12),
                Text(l10n.homeCollectionsIntro, style: Zt.body),
                const SizedBox(height: 30),
                if (_picked.isNotEmpty) ...[
                  SettingHeader(l10n.onHome, first: true),
                  for (final (i, (id, name)) in _picked.indexed)
                    Row(children: [
                      Expanded(
                        child: SettingToggleRow(
                          title: name,
                          value: true,
                          onChanged: (_) => _save([for (final c in _picked) if (c.$1 != id) c]),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Visibility(
                        visible: i > 0,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: TvButton(
                          label: l10n.moveUp,
                          icon: Icons.arrow_upward_rounded,
                          collapsed: true,
                          onSelect: () => _moveUp(i),
                        ),
                      ),
                    ]),
                ],
                SettingHeader(l10n.collections, first: _picked.isEmpty),
                if (all == null)
                  const Padding(padding: EdgeInsets.all(24), child: SkeletonBox(width: 600, height: 60, radius: 12))
                else if (all.isEmpty)
                  Text(l10n.homeCollectionsNone, style: Zt.body)
                else
                  for (final c in all)
                    if (!picked.contains(c.id))
                      SettingToggleRow(
                        title: c.name,
                        subtitle: c.childCount == null ? null : '${c.childCount}',
                        value: false,
                        onChanged: (_) => _save([..._picked, (c.id, c.name)]),
                      ),
              ]),
            );
          },
        ),
      ),
    );
  }
}
