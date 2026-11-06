import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/hub_link.dart';
import '../../data/seerr_api.dart';
import '../../l10n/l10n.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import 'common.dart';

bool canReportProblem(AppServices s) => HubLink.features.redownload && (s.seerr?.canRedownload ?? false);

Future<void> reportProblem(BuildContext context,
    {required String title, required int tmdbId, int? season, int? tvdbId}) async {
  final s = AppServicesScope.read(context);
  final seerr = s.seerr;
  if (seerr == null) return;
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportDialog(body: season == null ? l10n.reportMovieBody(title) : l10n.reportSeasonBody(title, season)),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await seerr.redownload(tmdbId, season == null ? SeerrMediaType.movie : SeerrMediaType.tv,
        season: season, tvdbId: tvdbId);
    if (context.mounted) showToast(context, l10n.reportSent);
    s.markLibraryChanged();
  } catch (e) {
    debugPrint('[report] $tmdbId season ${season ?? '-'}: $e');
    UiSounds.play(UiSound.error);
    if (context.mounted) showToast(context, l10n.reportFailed(e is SeerrException ? e.message : '$e'));
  }
}

class _ReportDialog extends StatelessWidget {
  const _ReportDialog({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      backgroundColor: Zc.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Zs.radiusLarge)),
      child: SizedBox(
        width: 900,
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: FocusZone(
            debugLabel: 'report-problem',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.report_problem_outlined, size: 48, color: Zc.accent),
                  const SizedBox(width: 24),
                  Expanded(child: Text(l10n.reportProblem, style: Zt.headline.copyWith(fontSize: 40))),
                ]),
                const SizedBox(height: 24),
                Text(body, style: Zt.body),
                const SizedBox(height: 36),
                Wrap(spacing: 18, runSpacing: 18, children: [
                  TvButton(label: l10n.cancel, icon: Icons.close_rounded, autofocus: true, onSelect: () => Navigator.of(context).pop(false)),
                  TvButton(label: l10n.reportConfirm, icon: Icons.restart_alt_rounded, primary: true, onSelect: () => Navigator.of(context).pop(true)),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
