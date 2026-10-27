import 'package:flutter/material.dart';

import '../../data/recommendations.dart';
import '../../data/seerr_api.dart';
import '../../data/title_tags.dart';
import '../../l10n/l10n.dart';
import '../../l10n/tag_names_ro.dart';
import '../core/navigation.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/media_row.dart';
import '../widgets/mixed_cards.dart';
import 'details_parts.dart';
import 'tag_page.dart';

void openTag(BuildContext context, TitleTag tag) =>
    Navigator.of(context).push(tvRoute(TagPage(tag: tag), name: 'tag:${tag.key}'));

bool _ro(L10n l10n) => l10n.localeName.startsWith('ro');

String lowerFirst(String s) =>
    s.length > 1 && s[1] == s[1].toLowerCase() ? s[0].toLowerCase() + s.substring(1) : s;

String tagLabel(L10n l10n, TitleTag tag) =>
    tag.isKeyword && _ro(l10n) ? (tagRo(tag.name)?.label ?? tag.name) : tag.name;

String? tagRowTitle(L10n l10n, TitleTag tag) {
  if (!_ro(l10n)) return l10n.becauseYouLikeTag(tag.name);
  if (tag.isKeyword) {
    final ro = tagRo(tag.name);
    return ro == null ? null : l10n.becauseYouLikeTag(ro.phrase);
  }
  final genres = tag.name.split(' · ').map(lowerFirst).join(' și ');
  return l10n.becauseYouLikeTag('${tag.type == SeerrMediaType.tv ? 'serialele' : 'filmele'} de $genres');
}

class TagRow extends StatelessWidget {
  const TagRow({super.key, required this.tags, this.left = pageLeft});

  final List<TitleTag> tags;
  final double left;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return MediaRow(
      left: left,
      title: context.l10n.tags,
      height: 84,
      gap: 14,
      itemCount: tags.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: _TagChip(tag: tags[i]),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});

  final TitleTag tag;

  @override
  Widget build(BuildContext context) => TvFocusable(
        onSelect: () => openTag(context, tag),
        builder: (context, focused) => AnimatedContainer(
          duration: Zm.fast,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: focused ? Colors.white : Zc.surfaceHigh.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(27),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(tag.isKeyword ? Icons.sell_outlined : Icons.category_outlined,
                size: 22, color: focused ? Zc.background : Zc.textMuted),
            const SizedBox(width: 10),
            Text(tagLabel(context.l10n, tag), style: Zt.label.copyWith(fontSize: 20, color: focused ? Zc.background : Zc.text)),
          ]),
        ),
      );
}

class MoreLikeThisRow extends StatelessWidget {
  const MoreLikeThisRow({super.key, required this.items, this.left = pageLeft});

  final MixedItems items;
  final double left;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return MediaRow(
      left: left,
      title: context.l10n.moreLikeThis,
      height: cardAreaHeight(CardStyle.poster),
      itemCount: items.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: mixedCard(context, items[i], style: CardStyle.poster),
      ),
    );
  }
}
