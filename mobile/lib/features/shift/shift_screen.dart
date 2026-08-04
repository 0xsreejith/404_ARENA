import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/core/money/money.dart';
import 'package:arena_os/features/checkout/checkout_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/permissions/permission_gate.dart';
import 'package:arena_os/features/shift/shift_controller.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShiftScreen extends ConsumerStatefulWidget {
  const ShiftScreen({super.key});

  @override
  ConsumerState<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends ConsumerState<ShiftScreen> {
  final _openingFloatController = TextEditingController();
  final _countedCashController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _openingFloatController.dispose();
    _countedCashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiftState = ref.watch(shiftControllerProvider);
    final tenant = ref.watch(tenantControllerProvider);
    final arenaId = tenant.selectedArena?['id'] as String?;
    final currency = tenant.currency;
    final primary = tenant.primaryColor;
    final current = shiftState.current;
    final summary = shiftState.summary;

    return ColoredBox(
      color: ArenaColors.background,
      child: shiftState.isLoading && current == null
          ? Center(child: CircularProgressIndicator(color: primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Refresh shift',
                    icon: const Icon(Icons.refresh, color: ArenaColors.textMuted),
                    onPressed: arenaId == null
                        ? null
                        : () => ref.read(shiftControllerProvider.notifier).load(arenaId),
                  ),
                ),
                if (shiftState.error != null) ...[
                  _ErrorBanner(message: shiftState.error!),
                  const SizedBox(height: 16),
                ],
                _StatusCard(
                  current: current,
                  currency: currency,
                  primary: primary,
                ),
                const SizedBox(height: 16),
                if (current == null)
                  PermissionGate(
                    permission: 'shift.open',
                    child: _Panel(
                      title: 'OPEN SHIFT',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _MoneyField(
                            controller: _openingFloatController,
                            label: 'OPENING FLOAT ($currency)',
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: ArenaColors.onAccent,
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: shiftState.isSubmitting ? null : () => _openShift(currency),
                            child: Text(
                              shiftState.isSubmitting ? 'OPENING...' : 'OPEN SHIFT',
                              style: LobbyFonts.display(size: 14, color: ArenaColors.onAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  _SummaryCard(summary: summary, currency: currency),
                  const SizedBox(height: 16),
                  PermissionGate(
                    permission: 'shift.close',
                    child: _Panel(
                      title: 'CLOSE SHIFT',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _MoneyField(
                            controller: _countedCashController,
                            label: 'COUNTED CASH ($currency)',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notesController,
                            minLines: 2,
                            maxLines: 4,
                            style: LobbyFonts.body(size: 14),
                            decoration: _inputDecoration('NOTES IF VARIANCE'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ArenaColors.danger,
                              side: const BorderSide(color: Color(0x66FF4444)),
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: shiftState.isSubmitting ? null : () => _closeShift(currency),
                            child: Text(
                              shiftState.isSubmitting ? 'CLOSING...' : 'CLOSE SHIFT',
                              style: LobbyFonts.display(size: 14, color: ArenaColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _openShift(String currency) async {
    final raw = _openingFloatController.text.trim();
    Money openingFloat;
    try {
      openingFloat = Money.parse(raw, currency);
    } on MoneyFormatException {
      _showSnack('Enter a valid opening float.');
      return;
    }
    if (openingFloat.isNegative) {
      _showSnack('Opening float cannot be negative.');
      return;
    }
    await ref.read(shiftControllerProvider.notifier).openShift(openingFloat.toDecimalString());
  }

  Future<void> _closeShift(String currency) async {
    final raw = _countedCashController.text.trim();
    Money countedCash;
    try {
      countedCash = Money.parse(raw, currency);
    } on MoneyFormatException {
      _showSnack('Enter a valid counted cash amount.');
      return;
    }
    if (countedCash.isNegative) {
      _showSnack('Counted cash cannot be negative.');
      return;
    }
    await ref.read(shiftControllerProvider.notifier).closeShift(
          countedCash: countedCash.toDecimalString(),
          notes: _notesController.text.trim(),
        );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.current,
    required this.currency,
    required this.primary,
  });

  final Map<String, dynamic>? current;
  final String currency;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final isOpen = current != null;
    return _Panel(
      title: 'CURRENT STATUS',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isOpen ? primary : ArenaColors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOpen ? 'SHIFT OPEN' : 'NO OPEN SHIFT',
                  style: LobbyFonts.display(size: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  isOpen
                      ? 'Opened ${_formatOpenedAt(current?['opened_at'])}'
                      : 'Open a shift before taking cash payments.',
                  style: LobbyFonts.body(
                    size: 13.5,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.55),
                  ),
                ),
                if (isOpen) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Float ${_money(current?['opening_float'], currency)}',
                    style: LobbyFonts.mono(
                      size: 13,
                      color: ArenaColors.textPrimary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.currency});

  final Map<String, dynamic>? summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final sales = Map<String, dynamic>.from(summary?['sales'] as Map? ?? const {});
    final payments = Map<String, dynamic>.from(summary?['payments_by_method'] as Map? ?? const {});
    return _Panel(
      title: 'SHIFT SUMMARY',
      child: Column(
        children: [
          _MetricRow('Opening float', _money(summary?['opening_float'], currency)),
          _MetricRow('Play sales', _money(sales['play'], currency)),
          _MetricRow('Product sales', _money(sales['product'], currency)),
          _MetricRow('Discounts', _money(summary?['discount_total'], currency)),
          _MetricRow('Tax', _money(summary?['tax_total'], currency)),
          const Divider(color: ArenaColors.divider, height: 20),
          _MetricRow('Cash payments', _money(payments['cash'], currency)),
          _MetricRow('UPI payments', _money(payments['upi'], currency)),
          _MetricRow('Card payments', _money(payments['card'], currency)),
          const Divider(color: ArenaColors.divider, height: 20),
          _MetricRow(
            'Expected cash',
            _money(summary?['expected_cash'], currency),
            valueColor: ArenaColors.accent,
            prominent: true,
          ),
          _MetricRow('Orders', '${summary?['order_count'] ?? 0}'),
          _MetricRow('Sessions', '${summary?['session_count'] ?? 0}'),
          _MetricRow('Unbilled sessions', '${summary?['unbilled_session_count'] ?? 0}'),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(
    this.label,
    this.value, {
    this.valueColor = ArenaColors.textPrimary,
    this.prominent = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LobbyFonts.body(
                size: 13.5,
                color: ArenaColors.textPrimary.withValues(alpha: 0.55),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: LobbyFonts.mono(
                size: prominent ? 16 : 13,
                weight: prominent ? FontWeight.w700 : FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: LobbyFonts.mono(size: 15),
      decoration: _inputDecoration(label),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ArenaColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: LobbyFonts.mono(
              size: 11,
              weight: FontWeight.w700,
              letterSpacing: 11 * 0.12,
              color: ArenaColors.textPrimary.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x26FF4444),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x4DFF4444)),
      ),
      child: Text(
        message,
        style: LobbyFonts.body(size: 13, color: ArenaColors.danger),
      ),
    );
  }
}

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: LobbyFonts.mono(
      size: 11,
      color: ArenaColors.textPrimary.withValues(alpha: 0.45),
    ),
    filled: true,
    fillColor: const Color(0xFF11131A),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0x14FFFFFF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: ArenaColors.accent),
    ),
  );
}

String _money(Object? raw, String currency) {
  if (raw == null) return formatMoney(Money.zero(currency), currency);
  if (raw is Money) return formatMoney(raw, currency);
  try {
    if (raw is String || raw is int) {
      return formatMoney(Money.tryParseNullable(raw, currency) ?? Money.zero(currency), currency);
    }
    // Postgres numeric sometimes arrives as double via JSON — display only.
    if (raw is num) {
      return formatMoney(Money.parse(raw.toStringAsFixed(2), currency), currency);
    }
  } on MoneyFormatException {
    return raw.toString();
  }
  return formatMoney(Money.zero(currency), currency);
}

String _formatOpenedAt(Object? raw) {
  if (raw == null) return '—';
  final parsed = DateTime.tryParse(raw.toString())?.toLocal();
  if (parsed == null) return raw.toString();
  final y = parsed.year.toString().padLeft(4, '0');
  final mo = parsed.month.toString().padLeft(2, '0');
  final d = parsed.day.toString().padLeft(2, '0');
  final h = parsed.hour.toString().padLeft(2, '0');
  final mi = parsed.minute.toString().padLeft(2, '0');
  return '$y-$mo-$d $h:$mi';
}
