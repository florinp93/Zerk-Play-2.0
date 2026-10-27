import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/updater/updater.dart';
import '../core/playback_launcher.dart';
import '../focus/focus_zone.dart';
import '../theme/tokens.dart';
import 'common.dart';

Future<void> checkForUpdate(BuildContext context, {bool quiet = true}) async {
  final l10n = context.l10n;
  final AppUpdate? update;
  try {
    update = await Updater.check();
  } catch (e) {
    debugPrint('[update] check: $e');
    if (!quiet && context.mounted) showToast(context, l10n.updateCheckFailed);
    return;
  }
  if (!context.mounted || (quiet && playbackActive)) return;
  if (update == null) {
    if (!quiet) showToast(context, l10n.upToDate);
    return;
  }
  await showDialog<void>(context: context, builder: (_) => _UpdateDialog(update: update!));
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});

  final AppUpdate update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  File? _file;
  double? _progress;
  bool _busy = false;
  String? _error;

  Future<void> _install() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = _file ??= await Updater.download(widget.update, onProgress: (v) {
        if (mounted) setState(() => _progress = v);
      });
      if (mounted) setState(() => _progress = null);
      await Updater.install(file);
      if (mounted) setState(() => _busy = false);
    } on UpdateNotAllowed {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.updateAllowInstalls;
        });
      }
    } catch (e) {
      debugPrint('[update] $e');
      _file = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.updateFailed('$e');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final progress = _progress;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: Zc.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Zs.radiusLarge)),
        child: SizedBox(
          width: 760,
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: FocusZone(
              debugLabel: 'update',
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.system_update_rounded, size: 48, color: Zc.accent),
                  const SizedBox(width: 24),
                  Expanded(child: Text(l10n.updateAvailable(widget.update.name), style: Zt.headline)),
                ]),
                const SizedBox(height: 20),
                Text(l10n.updateBody, style: Zt.body),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(_error!, style: Zt.body.copyWith(color: Zc.danger)),
                ],
                const SizedBox(height: 36),
                if (_busy) ...[
                  Text(
                    progress == null ? l10n.updateInstalling : l10n.updateDownloading('${(progress * 100).round()}'),
                    style: Zt.title,
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    color: Zc.accent,
                    backgroundColor: Zc.surfaceTop,
                  ),
                ] else
                  Wrap(spacing: 18, runSpacing: 18, children: [
                    TvButton(
                      label: l10n.updateNow,
                      icon: Icons.download_rounded,
                      primary: true,
                      autofocus: true,
                      onSelect: _install,
                    ),
                    TvButton(label: l10n.updateLater, icon: Icons.close_rounded, onSelect: () => Navigator.of(context).pop()),
                  ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
