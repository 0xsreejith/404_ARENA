import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/features/lobby_ui/demo_data.dart';
import 'package:arena_os/features/lobby_ui/lobby_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// S0 Staff login — tablet composition from `404 Lobby OS.dc.html`.
/// GestureDetector only; no Material buttons / InkWell.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lobbyUiProvider);
    final ctrl = ref.read(lobbyUiProvider.notifier);
    final selected = state.selectedStaff ?? DemoData.staff.firstWhere((s) => s.active);
    final activeStaff = DemoData.staff.where((s) => s.active).toList();
    final emailMode = state.authMode == LobbyAuthMode.email;

    return ColoredBox(
      color: ArenaColors.background,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1),
            radius: 1.15,
            colors: <Color>[Color(0xFF12121C), Color(0xFF07070A)],
            stops: <double>[0, 0.62],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 780;
            final blurb = emailMode ? DemoData.loginBlurbEmail : DemoData.loginBlurbPin;

            final left = SizedBox(
              width: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    DemoData.arenaMark,
                    style: LobbyFonts.display(
                      size: 64,
                      height: 0.92,
                    ).copyWith(
                      shadows: const <Shadow>[
                        Shadow(color: Color(0x597CFF4F), blurRadius: 40),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    DemoData.productName,
                    style: LobbyFonts.mono(
                      size: 13,
                      letterSpacing: 13 * 0.42,
                      color: ArenaColors.accent,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    blurb,
                    style: LobbyFonts.body(
                      size: 15,
                      height: 1.5,
                      color: ArenaColors.textPrimary.withValues(alpha: 0.5),
                    ),
                  ),
                  if (!emailMode) ...<Widget>[
                    const SizedBox(height: 22),
                    _ProfileList(
                      staff: activeStaff,
                      selected: selected,
                      onSelect: ctrl.selectStaff,
                    ),
                  ],
                ],
              ),
            );

            final right = emailMode
                ? _EmailPanel(
                    email: state.authEmail,
                    password: state.authPass,
                    error: state.authError,
                    onEmail: ctrl.setAuthEmail,
                    onPass: ctrl.setAuthPass,
                    onSignIn: ctrl.emailSignIn,
                    onToPin: () => ctrl.setAuthMode(LobbyAuthMode.pin),
                  )
                : _PinPad(
                    staff: selected,
                    pinLength: state.pin.length,
                    onKey: ctrl.pressPin,
                    pinError: state.pinError,
                    onToEmail: () => ctrl.setAuthMode(LobbyAuthMode.email),
                  );

            if (wide) {
              return Padding(
                padding: const EdgeInsets.all(50),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      left,
                      const SizedBox(width: 74),
                      right,
                    ],
                  ),
                ),
              );
            }

            final scale = (constraints.maxWidth / 860).clamp(0.72, 1.0);
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 24 * scale,
                vertical: 32 * scale,
              ),
              child: Center(
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        left,
                        const SizedBox(width: 48),
                        Flexible(child: right),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProfileList extends StatelessWidget {
  const _ProfileList({
    required this.staff,
    required this.selected,
    required this.onSelect,
  });

  final List<DemoStaff> staff;
  final DemoStaff selected;
  final ValueChanged<DemoStaff> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'WHO IS ON · ${staff.length} PROFILES',
          style: LobbyFonts.mono(
            size: 9.5,
            letterSpacing: 9.5 * 0.14,
            color: ArenaColors.textPrimary.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(height: 8),
        ...staff.map((s) {
          final on = s.id == selected.id;
          final owner = s.role == DemoStaffRole.owner;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(s),
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: on
                      ? ArenaColors.accent.withValues(alpha: 0.08)
                      : const Color(0xFFFFFFFF).withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: on
                        ? ArenaColors.accent.withValues(alpha: 0.34)
                        : const Color(0xFFFFFFFF).withValues(alpha: 0.09),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: owner
                            ? ArenaColors.warning.withValues(alpha: 0.16)
                            : ArenaColors.accent.withValues(alpha: 0.15),
                      ),
                      child: Text(
                        s.initials,
                        style: LobbyFonts.mono(
                          size: 12,
                          weight: FontWeight.w700,
                          color: owner ? ArenaColors.warning : ArenaColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            s.name,
                            style: LobbyFonts.body(size: 15, weight: FontWeight.w600),
                          ),
                          Text(
                            '${s.roleLabel}${on ? ' · LAST SHIFT' : ''}',
                            style: LobbyFonts.mono(
                              size: 9.5,
                              letterSpacing: 9.5 * 0.08,
                              color: on
                                  ? ArenaColors.accent
                                  : ArenaColors.textPrimary.withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      on ? '●' : '',
                      style: LobbyFonts.mono(size: 12, color: ArenaColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({
    required this.staff,
    required this.pinLength,
    required this.onKey,
    required this.onToEmail,
    this.pinError,
  });

  final DemoStaff staff;
  final int pinLength;
  final ValueChanged<String> onKey;
  final VoidCallback onToEmail;
  final String? pinError;

  static const _keys = <String>[
    '1', '2', '3',
    '4', '5', '6',
    '7', '8', '9',
    'del', '0', 'ok',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(staff.name, style: LobbyFonts.display(size: 23, height: 1.1)),
        const SizedBox(height: 3),
        Text(
          staff.roleLabel,
          style: LobbyFonts.mono(
            size: 9.5,
            letterSpacing: 9.5 * 0.12,
            color: ArenaColors.textPrimary.withValues(alpha: 0.38),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(4, (i) {
            final filled = i < pinLength;
            return Container(
              width: 18,
              height: 18,
              margin: EdgeInsets.only(left: i == 0 ? 0 : 14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? ArenaColors.accent : const Color(0x00000000),
                border: filled
                    ? null
                    : Border.all(
                        color: const Color(0xFFFFFFFF).withValues(alpha: 0.22),
                      ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Text(
          pinError ?? (pinLength == 0 ? 'ENTER 4-DIGIT PIN' : 'ENTERING PIN'),
          style: LobbyFonts.mono(
            size: 10.5,
            letterSpacing: 10.5 * 0.12,
            color: pinError != null
                ? ArenaColors.danger
                : pinLength > 0
                    ? ArenaColors.accent
                    : ArenaColors.textPrimary.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 3 * 98 + 2 * 12,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _keys.map((k) {
              final label = k == 'del' ? '⌫' : (k == 'ok' ? '→' : k);
              final accent = k == 'ok';
              final special = k == 'del' || k == 'ok';
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onKey(k),
                child: Container(
                  width: 98,
                  height: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent
                        ? ArenaColors.accent
                        : const Color(0xFFFFFFFF).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accent
                          ? ArenaColors.accent
                          : const Color(0xFFFFFFFF).withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    label,
                    style: LobbyFonts.mono(
                      size: special ? 24 : 30,
                      weight: FontWeight.w700,
                      color: accent ? ArenaColors.onAccent : ArenaColors.textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToEmail,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              alignment: Alignment.center,
              child: Text(
                'USE EMAIL & PASSWORD INSTEAD',
                style: LobbyFonts.mono(
                  size: 10.5,
                  letterSpacing: 10.5 * 0.1,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmailPanel extends StatelessWidget {
  const _EmailPanel({
    required this.email,
    required this.password,
    required this.onEmail,
    required this.onPass,
    required this.onSignIn,
    required this.onToPin,
    this.error,
  });

  final String email;
  final String password;
  final String? error;
  final ValueChanged<String> onEmail;
  final ValueChanged<String> onPass;
  final VoidCallback onSignIn;
  final VoidCallback onToPin;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 342,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'OWNER & MANAGER SIGN-IN',
            style: LobbyFonts.mono(
              size: 9.5,
              letterSpacing: 9.5 * 0.14,
              color: ArenaColors.textPrimary.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel('EMAIL'),
          const SizedBox(height: 7),
          _LobbyField(
            value: email,
            hint: 'you@404arena.in',
            obscure: false,
            onChanged: onEmail,
          ),
          const SizedBox(height: 16),
          _FieldLabel('PASSWORD'),
          const SizedBox(height: 7),
          _LobbyField(
            value: password,
            hint: '••••••••',
            obscure: true,
            onChanged: onPass,
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              error!,
              style: LobbyFonts.mono(size: 10.5, color: ArenaColors.danger),
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSignIn,
            child: Container(
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ArenaColors.accent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                'SIGN IN',
                style: LobbyFonts.display(
                  size: 15,
                  letterSpacing: 15 * 0.1,
                  color: ArenaColors.onAccent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Any email and password work in this prototype.',
            style: LobbyFonts.body(
              size: 12.5,
              color: ArenaColors.textPrimary.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToPin,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'USE STAFF PIN INSTEAD',
                  style: LobbyFonts.mono(
                    size: 10.5,
                    letterSpacing: 10.5 * 0.1,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: LobbyFonts.mono(
        size: 9.5,
        letterSpacing: 9.5 * 0.12,
        color: ArenaColors.textPrimary.withValues(alpha: 0.42),
      ),
    );
  }
}

class _LobbyField extends StatefulWidget {
  const _LobbyField({
    required this.value,
    required this.hint,
    required this.obscure,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final bool obscure;
  final ValueChanged<String> onChanged;

  @override
  State<_LobbyField> createState() => _LobbyFieldState();
}

class _LobbyFieldState extends State<_LobbyField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _LobbyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _c.text) {
      _c.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_focus, _c]),
      builder: (context, _) {
        final focused = _focus.hasFocus;
        final empty = _c.text.isEmpty;
        return Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: ArenaColors.panel,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: focused
                  ? ArenaColors.accent.withValues(alpha: 0.45)
                  : const Color(0xFFFFFFFF).withValues(alpha: 0.1),
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              if (empty)
                Text(
                  widget.hint,
                  style: LobbyFonts.body(
                    size: 15,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.28),
                  ),
                ),
              EditableText(
                controller: _c,
                focusNode: _focus,
                obscureText: widget.obscure,
                style: LobbyFonts.body(size: 15),
                cursorColor: ArenaColors.accent,
                backgroundCursorColor: ArenaColors.accent,
                onChanged: widget.onChanged,
              ),
            ],
          ),
        );
      },
    );
  }
}
