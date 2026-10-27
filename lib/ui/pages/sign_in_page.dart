import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../core/emby/server_kind.dart';
import '../../l10n/l10n.dart';
import '../core/ui_sounds.dart';
import '../focus/focus_zone.dart';
import '../focus/tv_focusable.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/remote_setup_panel.dart';
import '../widgets/zerk_logo.dart';
import 'onboarding_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  ServerKind _kind = ServerKind.emby;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final janus = AppServicesScope.read(context).janus;
    janus.getServerUrl().then((url) {
      if (mounted && url.isNotEmpty) _server.text = url;
    });
    janus.getServerKind().then((kind) {
      if (mounted) setState(() => _kind = kind);
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var url = _server.text.trim();
    if (url.isNotEmpty && !url.contains('://')) url = 'http://$url';
    try {
      await AppServicesScope.read(context).signIn(
          server: url, kind: _kind, username: _user.text.trim(), password: _pass.text);
    } catch (e) {
      UiSounds.play(UiSound.error);
      setState(() => _error = _describe(context.l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _describe(L10n l10n, Object e) {
    final s = '$e';
    if (s.contains('401')) return l10n.errorWrongCredentials;
    if (s.contains('SocketException') || s.contains('Connection')) return l10n.errorUnreachable;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final firstRun = !AppServicesScope.of(context).settings.onboarded;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: Alignment(-0.6, -0.6), radius: 1.4, colors: [Color(0xFF221E4A), Zc.background]),
              ),
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 640,
                  child: FocusZone(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ZerkLogo(size: 96),
                        const SizedBox(height: 36),
                        if (firstRun) ...[
                          Text(l10n.stepOf(1, OnboardingPage.stepCount + 1), style: Zt.caption.copyWith(color: Zc.accentSoft)),
                          const SizedBox(height: 10),
                        ],
                        Text(l10n.signInWelcome, style: Zt.display.copyWith(fontSize: 52)),
                        const SizedBox(height: 12),
                        Text(
                          l10n.signInSubtitle,
                          style: Zt.body,
                        ),
                        const SizedBox(height: 40),
                        _ServerKindPicker(value: _kind, onChanged: (k) => setState(() => _kind = k)),
                        _Field(controller: _server, label: l10n.serverAddress, hint: l10n.serverAddressHint),
                        _Field(controller: _user, label: l10n.username),
                        _Field(controller: _pass, label: l10n.password, obscure: true, onSubmit: _submit),
                        const SizedBox(height: 20),
                        TvButton(label: _busy ? l10n.signingIn : l10n.signIn, icon: Icons.login_rounded, primary: true, onSelect: _submit),
                        AnimatedSize(
                          duration: Zm.normal,
                          child: _error == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 20),
                                  child: Text(_error!, style: Zt.body.copyWith(color: Zc.danger)),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 90),
                Container(width: 1.5, height: 520, color: Zc.outline),
                const SizedBox(width: 90),
                const SizedBox(width: 760, child: RemoteSetupPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerKindPicker extends StatelessWidget {
  const _ServerKindPicker({required this.value, required this.onChanged});

  final ServerKind value;
  final ValueChanged<ServerKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(context.l10n.mediaServer, style: Zt.caption.copyWith(fontSize: 20)),
        ),
        Row(children: [
          for (final kind in ServerKind.values) ...[
            if (kind != ServerKind.values.first) const SizedBox(width: 16),
            Expanded(
              child: TvFocusable(
                autofocus: kind == value,
                onSelect: () => onChanged(kind),
                builder: (context, focused) {
                  final selected = kind == value;
                  return AnimatedContainer(
                    duration: Zm.fast,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? Zc.accent : (focused ? Zc.surfaceTop : Zc.surface),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: focused ? Colors.white : Zc.outline, width: focused ? 2.5 : 1.5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (selected) ...[const Icon(Icons.check_rounded, size: 26, color: Colors.white), const SizedBox(width: 8)],
                      Text(kind.label, style: Zt.label.copyWith(fontSize: 24, color: Colors.white)),
                    ]),
                  );
                },
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({required this.controller, required this.label, this.hint, this.obscure = false, this.onSubmit});

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final VoidCallback? onSubmit;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _node.hasFocus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: AnimatedContainer(
        duration: Zm.fast,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: focused ? Zc.surfaceTop : Zc.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: focused ? Colors.white : Zc.outline, width: focused ? 2.5 : 1.5),
        ),
        child: TextField(
          focusNode: _node,
          controller: widget.controller,
          obscureText: widget.obscure,
          autocorrect: false,
          enableSuggestions: false,
          style: Zt.label.copyWith(fontSize: 26, fontWeight: FontWeight.w500),
          cursorColor: Zc.accent,
          textInputAction: widget.onSubmit == null ? TextInputAction.next : TextInputAction.done,
          onSubmitted: (_) => widget.onSubmit != null ? widget.onSubmit!() : ZoneNavigator.move(TraversalDirection.down),
          decoration: InputDecoration(
            border: InputBorder.none,
            labelText: widget.label,
            hintText: widget.hint,
            labelStyle: Zt.caption.copyWith(fontSize: 20),
            hintStyle: Zt.caption.copyWith(fontSize: 22),
          ),
        ),
      ),
    );
  }
}
