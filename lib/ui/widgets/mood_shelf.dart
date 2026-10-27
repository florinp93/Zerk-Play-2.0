import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/models/emby_item.dart';
import '../../data/moods.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../core/navigation.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../pages/hero.dart';
import '../pages/mood_page.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'media_row.dart';
import 'net_image.dart';
import 'scroll_arrows.dart';

({String title, String tagline, IconData icon}) moodText(L10n l, Mood m) => switch (m.id) {
      'trueStory' => (title: l.moodTrueStory, tagline: l.moodTrueStoryHint, icon: Icons.history_edu_rounded),
      'heist' => (title: l.moodHeist, tagline: l.moodHeistHint, icon: Icons.diamond_outlined),
      'whodunit' => (title: l.moodWhodunit, tagline: l.moodWhodunitHint, icon: Icons.search_rounded),
      'mindBending' => (title: l.moodMindBending, tagline: l.moodMindBendingHint, icon: Icons.psychology_alt_rounded),
      'space' => (title: l.moodSpace, tagline: l.moodSpaceHint, icon: Icons.rocket_launch_rounded),
      'survival' => (title: l.moodSurvival, tagline: l.moodSurvivalHint, icon: Icons.local_fire_department_rounded),
      'revenge' => (title: l.moodRevenge, tagline: l.moodRevengeHint, icon: Icons.bolt_rounded),
      'conspiracy' => (title: l.moodConspiracy, tagline: l.moodConspiracyHint, icon: Icons.visibility_rounded),
      'roadTrip' => (title: l.moodRoadTrip, tagline: l.moodRoadTripHint, icon: Icons.directions_car_rounded),
      'comingOfAge' => (title: l.moodComingOfAge, tagline: l.moodComingOfAgeHint, icon: Icons.school_rounded),
      'feelGood' => (title: l.moodFeelGood, tagline: l.moodFeelGoodHint, icon: Icons.sentiment_very_satisfied_rounded),
      'serialKiller' => (title: l.moodSerialKiller, tagline: l.moodSerialKillerHint, icon: Icons.fingerprint_rounded),
      'lateNightHorror' => (title: l.moodLateNightHorror, tagline: l.moodLateNightHorrorHint, icon: Icons.nightlight_round),
      'classics' => (title: l.moodClassics, tagline: l.moodClassicsHint, icon: Icons.album_rounded),
      'hiddenGems' => (title: l.moodHiddenGems, tagline: l.moodHiddenGemsHint, icon: Icons.auto_awesome_rounded),
      'quickWatch' => (title: l.moodQuickWatch, tagline: l.moodQuickWatchHint, icon: Icons.timer_outlined),
      'bingeWorthy' => (title: l.moodBingeWorthy, tagline: l.moodBingeWorthyHint, icon: Icons.live_tv_rounded),
      _ => (title: m.id, tagline: '', icon: Icons.movie_filter_rounded),
    };

final class MoodPreview {
  const MoodPreview({this.titles = const [], this.inLibrary = 0});

  final List<String> titles;
  final int inLibrary;
}

class MoodShelf extends StatefulWidget {
  const MoodShelf({super.key, required this.favoriteGenres, required this.onFocusHero});

  final Future<List<String>> favoriteGenres;
  final ValueChanged<HeroInfo> onFocusHero;

  @override
  State<MoodShelf> createState() => _MoodShelfState();
}

class _MoodShelfState extends State<MoodShelf> {
  late final AppServices _s = AppServicesScope.read(context);
  late final Future<List<Mood>> _moods =
      widget.favoriteGenres.then((g) => Mood.pick(favoriteGenres: g), onError: (Object _) => Mood.pick(favoriteGenres: const []));
  final _previews = <String, Future<MoodPreview>>{};
  final _controller = RevealController(mode: RevealMode.anchored, anchor: contentLeft);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<MoodPreview> _preview(Mood m) => _previews.putIfAbsent(m.id, () async {
        final items = await m.items(_s.recommender, tv: m.movie == null, pages: 1);
        return MoodPreview(
          titles: [for (final i in items.take(3)) i is EmbyItem ? i.name : (i as SeerrMedia).title],
          inLibrary: items.whereType<EmbyItem>().length,
        );
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Mood>>(
      future: _moods,
      builder: (context, snap) {
        final moods = snap.data;
        if (moods == null || moods.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: Zs.rowGap),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(left: contentLeft, bottom: 18),
              child: Text(context.l10n.moodShelfTitle, style: Zt.rowTitle),
            ),
            SizedBox(
              height: MoodTile.height + 40,
              child: PointerScrollArrows(
                controller: _controller,
                leftInset: contentLeft,
                child: FocusZone(
                debugLabel: 'moods',
                child: ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.only(left: contentLeft, right: contentLeft, top: 14),
                  itemCount: moods.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Zs.cardGap),
                  itemBuilder: (context, i) {
                    final mood = moods[i];
                    return FutureBuilder<MoodPreview>(
                      future: _preview(mood),
                      builder: (context, p) => MoodTile(
                        mood: mood,
                        preview: p.data,
                        onFocus: () => _focus(mood, p.data),
                        onSelect: () => Navigator.of(context).push(tvRoute(MoodPage(mood: mood), name: 'mood:${mood.id}')),
                      ),
                    );
                  },
                ),
              ),
              ),
            ),
          ]),
        );
      },
    );
  }

  void _focus(Mood mood, MoodPreview? p) {
    final t = moodText(context.l10n, mood);
    widget.onFocusHero(HeroInfo(
      key: 'mood:${mood.id}',
      title: t.title,
      backdrop: mood.backdropUrl(width: 1280),
      overview: t.tagline,
      meta: [if (p != null && p.titles.isNotEmpty) p.titles.join(' · ')],
    ));
  }
}

class MoodTile extends StatelessWidget {
  const MoodTile({super.key, required this.mood, this.preview, this.onFocus, this.onSelect});

  static const width = Zs.landscapeWidth;
  static const height = Zs.landscapeWidth * 9 / 16;

  final Mood mood;
  final MoodPreview? preview;
  final VoidCallback? onFocus;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final t = moodText(context.l10n, mood);
    final color = Color(mood.color);
    final p = preview;
    return TvFocusable(
      onSelect: onSelect,
      onFocusChange: (f) => f ? onFocus?.call() : null,
      builder: (context, focused) => FocusFrame(
        focused: focused,
        scale: 1.06,
        radius: Zs.radiusLarge,
        glowColor: color,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: Color.lerp(color, Zc.background, 0.55)!),
            AnimatedOpacity(
              opacity: focused ? 1 : 0.7,
              duration: Zm.normal,
              child: AnimatedScale(
                scale: focused ? 1.12 : 1,
                duration: focused ? const Duration(seconds: 8) : Zm.slow,
                curve: focused ? Curves.easeOut : Zm.curve,
                child: NetImage(url: mood.backdropUrl(), width: width, fallback: const SizedBox.shrink()),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    Color.lerp(color, Colors.black, 0.55)!.withValues(alpha: 0.95),
                    color.withValues(alpha: focused ? 0.15 : 0.45),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 10),
                    ]),
                    child: Icon(t.icon, color: Colors.white, size: 26),
                  ),
                  const Spacer(),
                  if (p != null && p.inLibrary > 0)
                    Pill(context.l10n.moodInLibrary(p.inLibrary), color: Colors.black.withValues(alpha: 0.55)),
                ]),
                const Spacer(),
                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Zt.title),
                const SizedBox(height: 4),
                Text(
                  p == null || p.titles.isEmpty ? t.tagline : p.titles.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Zt.caption.copyWith(color: Zc.textMuted),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
