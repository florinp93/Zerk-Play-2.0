import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_services.dart';
import '../../app/hub_link.dart';
import '../../app/release.dart';
import '../../core/emby/server_kind.dart';
import '../../core/host.dart';
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
  final _code = TextEditingController(text: _CodeFormatter.format(HubLink.code ?? ''));
  final _hub = TextEditingController(text: HubLink.hub);
  final _userNode = FocusNode();
  ServerKind _kind = ServerKind.emby;
  bool _manual = false;
  String? _error = HubLink.droppedMessage;
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

  @override
  void dispose() {
    for (final c in [_server, _user, _pass, _code, _hub]) {
      c.dispose();
    }
    _userNode.dispose();
    super.dispose();
  }

  void _showManual(bool manual) {
    UiSounds.play(UiSound.select);
    setState(() {
      _manual = manual;
      _error = null;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on HubLinkException catch (e) {
      UiSounds.play(UiSound.error);
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      UiSounds.play(UiSound.error);
      if (mounted) setState(() => _error = _describe(context.l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redeem() => _run(() async {
        final code = _code.text.trim();
        if (code.isEmpty) return;
        await AppServicesScope.read(context).linkHub(code, hub: _hub.text);
        if (!mounted) return;
        UiSounds.play(UiSound.select);
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _userNode.requestFocus();
        });
      });

  Future<void> _signInLinked() => _run(() async {
        final config = HubLink.config!;
        await AppServicesScope.read(context).signIn(
            server: config.serverUrl, kind: config.serverKind, username: _user.text.trim(), password: _pass.text);
      });

  Future<void> _signInManual() => _run(() async {
        var url = _server.text.trim();
        if (url.isNotEmpty && !url.contains('://')) url = 'http://$url';
        await AppServicesScope.read(context)
            .signIn(server: url, kind: _kind, username: _user.text.trim(), password: _pass.text);
      });

  Future<void> _otherCode() async {
    await AppServicesScope.read(context).unlinkHub();
    if (!mounted) return;
    setState(() {
      _code.clear();
      _error = null;
    });
  }

  static String _describe(L10n l10n, Object e) {
    final s = '$e';
    if (s.contains('401')) return l10n.errorWrongCredentials;
    if (s.contains('SocketException') || s.contains('Connection')) return l10n.errorUnreachable;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final firstRun = !AppServicesScope.of(context).settings.onboarded;
    return PopScope(
      canPop: !_manual,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _manual) _showManual(false);
      },
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: _Backdrop()),
            Center(
              child: AnimatedSwitcher(
                duration: Zm.slow,
                switchInCurve: Zm.curve,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: _manual
                    ? KeyedSubtree(key: const ValueKey('manual'), child: _manualLayout(context, firstRun))
                    : KeyedSubtree(key: const ValueKey('code'), child: _codeLayout(context, firstRun)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorText() => AnimatedSize(
        duration: Zm.normal,
        child: _error == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(_error!, style: Zt.body.copyWith(color: Zc.danger)),
              ),
      );

  Widget _codeLayout(BuildContext context, bool firstRun) {
    final l10n = context.l10n;
    final linked = HubLink.linked;
    final site = Uri.tryParse(Release.hub)?.host ?? '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 800,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ZerkLogo(size: 96),
              const SizedBox(height: 40),
              if (firstRun) ...[
                Text(l10n.stepOf(1, OnboardingPage.stepCount + 1), style: Zt.caption.copyWith(color: Zc.accentSoft)),
                const SizedBox(height: 12),
              ],
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(
                  colors: [Colors.white, Color(0xFFD9D6FF), Zc.accentSoft],
                  stops: [0, 0.55, 1],
                ).createShader(r),
                child: Text(l10n.codeHeadline, style: Zt.display.copyWith(fontSize: 62, height: 1.08)),
              ),
              const SizedBox(height: 22),
              Text(l10n.codePitch, style: Zt.body.copyWith(fontSize: 24)),
              const SizedBox(height: 40),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  _Feature(icon: Icons.add_circle_outline_rounded, color: Zc.request, text: l10n.codeFeatureRequests),
                  _Feature(icon: Icons.groups_rounded, color: Zc.cinema, text: l10n.codeFeatureTogether),
                  _Feature(icon: Icons.account_circle_rounded, color: Zc.accentSoft, text: l10n.codeFeatureProfiles),
                  _Feature(icon: Icons.live_tv_rounded, color: Zc.success, text: l10n.codeFeatureLiveTv),
                ],
              ),
              if (site.isNotEmpty) ...[
                const SizedBox(height: 40),
                Text(l10n.codeOwnerHint(site), style: Zt.caption.copyWith(fontSize: 20)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 110),
        SizedBox(
          width: 640,
          child: FocusZone(
            child: Container(
              padding: const EdgeInsets.fromLTRB(44, 42, 44, 36),
              decoration: BoxDecoration(
                color: Zc.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Zc.outline, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Zc.accent.withValues(alpha: 0.22), blurRadius: 90, spreadRadius: -10),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!linked) ...[
                    Text(l10n.codeEnterTitle, style: Zt.headline.copyWith(fontSize: 36)),
                    const SizedBox(height: 8),
                    Text(l10n.codeEnterHint, style: Zt.caption.copyWith(fontSize: 20)),
                    const SizedBox(height: 28),
                    _Field(
                      controller: _code,
                      hint: 'XXXX-XXXX-XXXX',
                      code: true,
                      autofocus: Host.isDesktop,
                      onSubmit: _redeem,
                    ),
                    if (Release.hub.isEmpty || _hub.text != Release.hub)
                      _Field(controller: _hub, label: l10n.hubAddress, hint: l10n.hubAddressHint),
                    const SizedBox(height: 8),
                    TvButton(
                      label: _busy ? l10n.codeChecking : l10n.codeContinue,
                      icon: Icons.arrow_forward_rounded,
                      primary: true,
                      autofocus: !Host.isDesktop,
                      onSelect: _redeem,
                    ),
                  ] else ...[
                    Row(children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(color: Zc.success.withValues(alpha: 0.16), shape: BoxShape.circle),
                        child: const Icon(Icons.verified_rounded, color: Zc.success, size: 32),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l10n.codeEyebrow(HubLink.config!.serverName),
                              style: Zt.label.copyWith(fontSize: 24), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(_CodeFormatter.format(HubLink.code ?? ''),
                              style: Zt.caption.copyWith(fontSize: 18, letterSpacing: 2)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 30),
                    Text(l10n.codeSignInTitle, style: Zt.headline.copyWith(fontSize: 36)),
                    const SizedBox(height: 8),
                    Text(l10n.codeSignInBody(HubLink.config!.serverKind.label), style: Zt.caption.copyWith(fontSize: 20)),
                    const SizedBox(height: 26),
                    _Field(controller: _user, label: l10n.username, focusNode: _userNode, autofocus: Host.isDesktop),
                    _Field(controller: _pass, label: l10n.password, obscure: true, onSubmit: _signInLinked),
                    const SizedBox(height: 8),
                    Row(children: [
                      TvButton(
                        label: _busy ? l10n.signingIn : l10n.signIn,
                        icon: Icons.login_rounded,
                        primary: true,
                        autofocus: !Host.isDesktop,
                        onSelect: _signInLinked,
                      ),
                      const SizedBox(width: 16),
                      TvButton(label: l10n.unlinkHub, icon: Icons.swap_horiz_rounded, onSelect: _otherCode),
                    ]),
                  ],
                  _errorText(),
                  const SizedBox(height: 30),
                  Container(height: 1.5, color: Zc.outline),
                  const SizedBox(height: 26),
                  Text(l10n.codeNoCode, style: Zt.caption.copyWith(fontSize: 20)),
                  const SizedBox(height: 16),
                  TvButton(label: l10n.signInManually, icon: Icons.tune_rounded, onSelect: () => _showManual(true)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _manualLayout(BuildContext context, bool firstRun) {
    final l10n = context.l10n;
    return Row(
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
                Text(l10n.signInSubtitle, style: Zt.body),
                const SizedBox(height: 32),
                _Choice<ServerKind>(
                  title: l10n.mediaServer,
                  values: ServerKind.values,
                  value: _kind,
                  label: (k) => k.label,
                  onChanged: (k) => setState(() => _kind = k),
                ),
                _Field(controller: _server, label: l10n.serverAddress, hint: l10n.serverAddressHint),
                _Field(controller: _user, label: l10n.username),
                _Field(controller: _pass, label: l10n.password, obscure: true, onSubmit: _signInManual),
                const SizedBox(height: 20),
                Row(children: [
                  TvButton(
                    label: _busy ? l10n.signingIn : l10n.signIn,
                    icon: Icons.login_rounded,
                    primary: true,
                    autofocus: true,
                    onSelect: _signInManual,
                  ),
                  const SizedBox(width: 16),
                  TvButton(label: l10n.codeBack, icon: Icons.qr_code_2_rounded, onSelect: () => _showManual(false)),
                ]),
                _errorText(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 90),
        Container(width: 1.5, height: 520, color: Zc.outline),
        const SizedBox(width: 90),
        const SizedBox(width: 760, child: RemoteSetupPanel()),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Zc.background),
      child: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.75, -0.7),
                radius: 1.25,
                colors: [Color(0xFF2A2464), Color(0x00221E4A)],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.95, 0.9),
                radius: 1.1,
                colors: [Color(0x5547234F), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 391,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Zc.outline, width: 1.2),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(text, style: Zt.label.copyWith(fontSize: 20, height: 1.3), maxLines: 2)),
      ]),
    );
  }
}

class _CodeFormatter extends TextInputFormatter {
  static String format(String raw) {
    final clean = raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final capped = clean.length > 12 ? clean.substring(0, 12) : clean;
    final out = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i > 0 && i % 4 == 0) out.write('-');
      out.write(capped[i]);
    }
    return out.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = format(newValue.text);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({required this.values, required this.value, required this.label, required this.onChanged, this.title});

  final List<T> values;
  final T value;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(title!, style: Zt.caption.copyWith(fontSize: 20)),
          ),
        Row(children: [
          for (final kind in values) ...[
            if (kind != values.first) const SizedBox(width: 16),
            Expanded(
              child: TvFocusable(
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
                      Flexible(
                        child: Text(label(kind),
                            style: Zt.label.copyWith(fontSize: 24, color: Colors.white), overflow: TextOverflow.ellipsis),
                      ),
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
  const _Field({
    required this.controller,
    this.label,
    this.hint,
    this.obscure = false,
    this.onSubmit,
    this.code = false,
    this.autofocus = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool obscure;
  final bool code;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onSubmit;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  FocusNode? _own;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _node.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _node.hasFocus;
    final code = widget.code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: AnimatedContainer(
        duration: Zm.fast,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: code ? 16 : 10),
        decoration: BoxDecoration(
          color: focused ? Zc.surfaceTop : Zc.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: focused ? Colors.white : Zc.outline, width: focused ? 2.5 : 1.5),
        ),
        child: TextField(
          focusNode: _node,
          autofocus: widget.autofocus,
          controller: widget.controller,
          obscureText: widget.obscure,
          textAlign: code ? TextAlign.center : TextAlign.start,
          textCapitalization: code ? TextCapitalization.characters : TextCapitalization.none,
          inputFormatters: code ? [_CodeFormatter()] : null,
          keyboardType: code ? TextInputType.visiblePassword : null,
          autocorrect: false,
          enableSuggestions: false,
          style: code
              ? Zt.display.copyWith(fontSize: 46, letterSpacing: 6, fontFeatures: const [FontFeature.tabularFigures()])
              : Zt.label.copyWith(fontSize: 26, fontWeight: FontWeight.w500),
          cursorColor: Zc.accent,
          textInputAction: widget.onSubmit == null ? TextInputAction.next : TextInputAction.done,
          onSubmitted: (_) => widget.onSubmit != null ? widget.onSubmit!() : ZoneNavigator.move(TraversalDirection.down),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: code,
            labelText: widget.label,
            hintText: widget.hint,
            labelStyle: Zt.caption.copyWith(fontSize: 20),
            hintStyle: code
                ? Zt.display.copyWith(fontSize: 46, letterSpacing: 6, color: Zc.textFaint.withValues(alpha: 0.25))
                : Zt.caption.copyWith(fontSize: 22),
          ),
        ),
      ),
    );
  }
}
