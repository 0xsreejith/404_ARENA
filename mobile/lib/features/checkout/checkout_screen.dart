import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/core/money/money.dart';
import 'package:arena_os/features/checkout/checkout_controller.dart';
import 'package:arena_os/features/lobby_ui/lobby_fonts.dart';
import 'package:arena_os/features/permissions/permission_gate.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Checkout / bill sheet — totals from `order_preview` only (D05).
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    required this.orderId,
    this.sessionId,
    this.memberName,
    super.key,
  });

  final String orderId;
  final String? sessionId;
  final String? memberName;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _selectedMethod = 'cash';
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  final _discountValueController = TextEditingController();
  String _discountKind = 'flat';
  bool _seededAmount = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(checkoutControllerProvider.notifier).openAndLoadCheckout(
            orderId: widget.orderId,
            sessionId: widget.sessionId,
          );
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    _discountValueController.dispose();
    super.dispose();
  }

  void _showDiscountDialog() {
    final currency = ref.read(tenantControllerProvider).currency;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ArenaColors.sheet,
        title: Text(
          'APPLY MANAGER DISCOUNT',
          style: LobbyFonts.display(size: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _discountKind,
                dropdownColor: ArenaColors.surfaceRaised,
                style: LobbyFonts.body(size: 14),
                decoration: InputDecoration(
                  labelText: 'DISCOUNT TYPE',
                  labelStyle: LobbyFonts.mono(
                    size: 11,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                  ),
                ),
                items: [
                  DropdownMenuItem(value: 'flat', child: Text('Flat amount ($currency)')),
                  const DropdownMenuItem(value: 'percent', child: Text('Percentage (%)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _discountKind = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _discountValueController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: LobbyFonts.mono(size: 14),
                decoration: InputDecoration(
                  labelText: 'VALUE',
                  labelStyle: LobbyFonts.mono(
                    size: 11,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                style: LobbyFonts.body(size: 14),
                decoration: InputDecoration(
                  labelText: 'REASON (REQUIRED)',
                  labelStyle: LobbyFonts.mono(
                    size: 11,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'CANCEL',
              style: LobbyFonts.mono(
                size: 12,
                color: ArenaColors.textPrimary.withValues(alpha: 0.55),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final raw = _discountValueController.text.trim();
              final reason = _reasonController.text.trim();
              if (reason.isEmpty || raw.isEmpty) return;
              Money value;
              try {
                value = Money.parse(raw, currency);
              } on MoneyFormatException {
                return;
              }
              if (!value.isPositive) return;

              Navigator.of(dialogContext).pop();
              await ref.read(checkoutControllerProvider.notifier).applyDiscount(
                    orderId: widget.orderId,
                    discountKind: _discountKind,
                    discountValue: value,
                    discountReason: reason,
                  );
            },
            child: const Text('APPLY'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkoutState = ref.watch(checkoutControllerProvider);
    final tenantState = ref.watch(tenantControllerProvider);
    final primaryColor = tenantState.primaryColor;
    final currency = tenantState.currency;

    if (checkoutState.isLoading && checkoutState.total == null) {
      return Scaffold(
        backgroundColor: ArenaColors.background,
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    final balance = checkoutState.balanceDue ?? Money.zero(currency);
    if (!_seededAmount && balance.isPositive) {
      _amountController.text = balance.toDecimalString();
      _seededAmount = true;
    }

    // Scaffold root guarantees Material for TextField / SegmentedButton
    // even if the shell chrome omits it.
    return Scaffold(
      backgroundColor: ArenaColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/floor');
                  }
                },
                icon: Icon(
                  Icons.arrow_back,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.7),
                  size: 18,
                ),
                label: Text(
                  'BACK TO FLOOR',
                  style: LobbyFonts.mono(
                    size: 11,
                    letterSpacing: 11 * 0.08,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
            if (widget.memberName != null) ...[
              Text(
                widget.memberName!,
                style: LobbyFonts.body(
                  size: 13,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (checkoutState.error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x26FF4444),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x4DFF4444)),
                ),
                child: Text(
                  checkoutState.error!,
                  style: LobbyFonts.body(size: 13, color: ArenaColors.danger),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (checkoutState.settledReceiptNumber != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: primaryColor, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ORDER SETTLED', style: LobbyFonts.display(size: 14)),
                          Text(
                            'RECEIPT: ${checkoutState.settledReceiptNumber}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: LobbyFonts.mono(
                              size: 13,
                              weight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'ITEMIZED BREAKDOWN',
              style: LobbyFonts.mono(
                size: 11,
                weight: FontWeight.w700,
                letterSpacing: 11 * 0.12,
                color: ArenaColors.textPrimary.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ArenaColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: checkoutState.items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No line items yet',
                          style: LobbyFonts.body(
                            size: 13,
                            color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < checkoutState.items.length; i++) ...[
                          if (i > 0) const Divider(color: Colors.white10),
                          _LineItemRow(
                            name: checkoutState.items[i].name,
                            detail:
                                'Qty: ${checkoutState.items[i].quantityLabel} @ ${formatMoney(checkoutState.items[i].unitPrice, currency)}',
                            amount: formatMoney(checkoutState.items[i].lineTotal, currency),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ArenaColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Column(
                children: [
                  _totalRow('SUBTOTAL', formatMoney(checkoutState.subtotal, currency)),
                  if ((checkoutState.discountTotal?.isPositive) ?? false)
                    _totalRow(
                      'DISCOUNT',
                      '-${formatMoney(checkoutState.discountTotal, currency)}',
                      color: ArenaColors.warning,
                    ),
                  _totalRow(
                    checkoutState.pricesIncludeTax ? 'TAX (INCLUDED)' : 'TAX',
                    formatMoney(checkoutState.taxTotal, currency),
                  ),
                  const Divider(color: Colors.white12),
                  Row(
                    children: [
                      Text(
                        'TOTAL',
                        style: LobbyFonts.mono(
                          size: 10,
                          letterSpacing: 10 * 0.12,
                          color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          formatMoney(checkoutState.total, currency),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LobbyFonts.mono(
                            size: 26,
                            weight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _totalRow('BALANCE DUE', formatMoney(checkoutState.balanceDue, currency)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PermissionGate(
                  permission: 'discount.apply',
                  child: OutlinedButton.icon(
                    onPressed: checkoutState.settledReceiptNumber != null
                        ? null
                        : _showDiscountDialog,
                    icon: const Icon(Icons.local_offer, size: 16),
                    label: const Text('DISCOUNT'),
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cash', label: Text('CASH')),
                    ButtonSegment(value: 'upi', label: Text('UPI')),
                    ButtonSegment(value: 'card', label: Text('CARD')),
                  ],
                  selected: {_selectedMethod},
                  onSelectionChanged: checkoutState.settledReceiptNumber != null
                      ? null
                      : (set) => setState(() => _selectedMethod = set.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Material(
              type: MaterialType.transparency,
              child: TextField(
                controller: _amountController,
                enabled: checkoutState.settledReceiptNumber == null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: LobbyFonts.mono(size: 15),
                decoration: InputDecoration(
                  labelText: 'PAYMENT AMOUNT ($currency)',
                  labelStyle: LobbyFonts.mono(
                    size: 11,
                    color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                  ),
                  filled: true,
                  fillColor: ArenaColors.panel,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            PermissionGate(
              permission: 'payment.create',
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: ArenaColors.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size.fromHeight(58),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: checkoutState.settledReceiptNumber != null || !balance.isPositive
                      ? null
                      : () async {
                          Money amt;
                          try {
                            amt = Money.parse(_amountController.text.trim(), currency);
                          } on MoneyFormatException {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Enter a valid payment amount.')),
                            );
                            return;
                          }
                          await ref.read(checkoutControllerProvider.notifier).settlePayment(
                                orderId: widget.orderId,
                                method: _selectedMethod,
                                amount: amt,
                              );
                        },
                  child: Text(
                    'TAKE PAYMENT & PRINT',
                    style: LobbyFonts.display(size: 15, color: ArenaColors.onAccent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, {Color? color}) {
    final c = color ?? ArenaColors.textPrimary.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LobbyFonts.body(size: 13, color: c),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: LobbyFonts.mono(size: 13, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({
    required this.name,
    required this.detail,
    required this.amount,
  });

  final String name;
  final String detail;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LobbyFonts.body(size: 14, weight: FontWeight.w600),
              ),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LobbyFonts.mono(
                  size: 12,
                  color: ArenaColors.textPrimary.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          amount,
          style: LobbyFonts.mono(size: 13, weight: FontWeight.w700),
        ),
      ],
    );
  }
}
