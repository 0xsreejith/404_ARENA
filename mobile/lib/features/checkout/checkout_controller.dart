import 'dart:math';

import 'package:arena_os/core/errors/app_failure.dart';
import 'package:arena_os/core/errors/failure_mapper.dart';
import 'package:arena_os/core/money/money.dart';
import 'package:arena_os/features/checkout/checkout_repository.dart';
import 'package:arena_os/features/devices/device_repository.dart';
import 'package:arena_os/features/tenant/tenant_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CheckoutLine {
  const CheckoutLine({
    required this.id,
    required this.name,
    required this.quantityLabel,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String id;
  final String name;
  final String quantityLabel;
  final Money unitPrice;
  final Money lineTotal;
}

class CheckoutState {
  const CheckoutState({
    this.currency = 'INR',
    this.pricesIncludeTax = true,
    this.subtotal,
    this.discountTotal,
    this.taxTotal,
    this.total,
    this.paidTotal,
    this.balanceDue,
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.settledReceiptNumber,
  });

  final String currency;
  final bool pricesIncludeTax;
  final Money? subtotal;
  final Money? discountTotal;
  final Money? taxTotal;
  final Money? total;
  final Money? paidTotal;
  final Money? balanceDue;
  final List<CheckoutLine> items;
  final bool isLoading;
  final String? error;
  final String? settledReceiptNumber;

  CheckoutState copyWith({
    String? currency,
    bool? pricesIncludeTax,
    Money? subtotal,
    Money? discountTotal,
    Money? taxTotal,
    Money? total,
    Money? paidTotal,
    Money? balanceDue,
    List<CheckoutLine>? items,
    bool? isLoading,
    String? error,
    String? settledReceiptNumber,
    bool clearError = false,
    bool clearReceipt = false,
  }) {
    return CheckoutState(
      currency: currency ?? this.currency,
      pricesIncludeTax: pricesIncludeTax ?? this.pricesIncludeTax,
      subtotal: subtotal ?? this.subtotal,
      discountTotal: discountTotal ?? this.discountTotal,
      taxTotal: taxTotal ?? this.taxTotal,
      total: total ?? this.total,
      paidTotal: paidTotal ?? this.paidTotal,
      balanceDue: balanceDue ?? this.balanceDue,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      settledReceiptNumber:
          clearReceipt ? null : (settledReceiptNumber ?? this.settledReceiptNumber),
    );
  }
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutControllerNotifier, CheckoutState>(CheckoutControllerNotifier.new);

class CheckoutControllerNotifier extends Notifier<CheckoutState> {
  @override
  CheckoutState build() => const CheckoutState();

  String get _currency => ref.read(tenantControllerProvider).currency;

  Future<void> openAndLoadCheckout({
    required String orderId,
    String? sessionId,
    String? memberId,
  }) async {
    final tenantState = ref.read(tenantControllerProvider);
    final arenaId = tenantState.selectedArena?['id'] as String?;
    if (arenaId == null) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearReceipt: true,
      currency: tenantState.currency,
    );
    try {
      final repo = ref.read(checkoutRepositoryProvider);
      await repo.openCheckout(
        arenaId: arenaId,
        orderId: orderId,
        sessionId: sessionId,
        memberId: memberId,
      );
      await _loadPreview(arenaId: arenaId, orderId: orderId);
      ref.read(lastServerContactProvider.notifier).touch();
    } catch (e, st) {
      final failure = e is AppFailure ? e : failureMapper.map(e, st);
      state = state.copyWith(isLoading: false, error: failure.message);
    }
  }

  Future<void> applyDiscount({
    required String orderId,
    required String discountKind,
    required Money discountValue,
    required String discountReason,
  }) async {
    final arenaId = ref.read(tenantControllerProvider).selectedArena?['id'] as String?;
    if (arenaId == null) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = ref.read(checkoutRepositoryProvider);
      await repo.applyDiscount(
        arenaId: arenaId,
        orderId: orderId,
        discountKind: discountKind,
        discountValue: discountKind == 'percent'
            ? discountValue.toDecimalString()
            : discountValue.toDecimalString(),
        discountReason: discountReason,
      );
      await _loadPreview(arenaId: arenaId, orderId: orderId);
    } catch (e, st) {
      final failure = e is AppFailure ? e : failureMapper.map(e, st);
      state = state.copyWith(isLoading: false, error: failure.message);
    }
  }

  Future<bool> settlePayment({
    required String orderId,
    required String method,
    required Money amount,
    String? reference,
  }) async {
    final arenaId = ref.read(tenantControllerProvider).selectedArena?['id'] as String?;
    if (arenaId == null) return false;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = ref.read(checkoutRepositoryProvider);
      final result = await repo.settlePayment(
        arenaId: arenaId,
        orderId: orderId,
        paymentId: _newUuidV4(),
        method: method,
        amount: amount.toDecimalString(),
        reference: reference,
      );

      final receiptNum = result['receipt_number'] as String?;
      await _loadPreview(arenaId: arenaId, orderId: orderId);
      state = state.copyWith(
        isLoading: false,
        settledReceiptNumber: receiptNum,
      );
      ref.read(lastServerContactProvider.notifier).touch();
      return result['status'] == 'settled';
    } catch (e, st) {
      final failure = e is AppFailure ? e : failureMapper.map(e, st);
      state = state.copyWith(isLoading: false, error: failure.message);
      return false;
    }
  }

  Future<void> _loadPreview({required String arenaId, required String orderId}) async {
    final repo = ref.read(checkoutRepositoryProvider);
    final preview = await repo.fetchOrderPreview(arenaId: arenaId, orderId: orderId);
    final currency = _currency;

    Money money(Object? raw) {
      if (raw == null) return Money.zero(currency);
      if (raw is String) return Money.parse(raw, currency);
      throw MoneyFormatException('$raw', 'expected decimal string from order_preview (D01)');
    }

    final items = ((preview['items'] as List<dynamic>?) ?? [])
        .map((e) {
          final row = Map<String, dynamic>.from(e as Map);
          return CheckoutLine(
            id: row['id'] as String? ?? '',
            name: row['name'] as String? ?? 'Item',
            quantityLabel: '${row['quantity'] ?? '1'}',
            unitPrice: money(row['unit_price']),
            lineTotal: money(row['line_total']),
          );
        })
        .toList();

    state = state.copyWith(
      currency: currency,
      pricesIncludeTax: preview['prices_include_tax'] as bool? ?? true,
      subtotal: money(preview['subtotal']),
      discountTotal: money(preview['discount_total']),
      taxTotal: money(preview['tax_total']),
      total: money(preview['total']),
      paidTotal: money(preview['paid_total']),
      balanceDue: money(preview['balance_due']),
      items: items,
      isLoading: false,
      clearError: true,
    );
  }

  static String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// Display helper — currency code from arena, never a hardcoded symbol (D31).
String formatMoney(Money? amount, String currency) {
  final value = amount ?? Money.zero(currency);
  return '${value.toGroupedString()} $currency';
}
