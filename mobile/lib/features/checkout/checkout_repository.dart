import 'package:arena_os/app/bootstrap.dart';
import 'package:arena_os/core/errors/failure_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CheckoutRepository {
  CheckoutRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<Map<String, dynamic>> openCheckout({
    required String arenaId,
    required String orderId,
    String? sessionId,
    String? memberId,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'checkout_open',
        params: {
          'p_arena_id': arenaId,
          'p_order_id': orderId,
          'p_session_id': sessionId,
          'p_member_id': memberId,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> fetchOrderPreview({
    required String arenaId,
    required String orderId,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'order_preview',
        params: {
          'p_arena_id': arenaId,
          'p_order_id': orderId,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<void> applyDiscount({
    required String arenaId,
    required String orderId,
    required String discountKind,
    required String discountValue,
    required String discountReason,
  }) async {
    try {
      await _supabase.rpc<dynamic>(
        'order_apply_discount',
        params: {
          'p_arena_id': arenaId,
          'p_order_id': orderId,
          'p_discount_kind': discountKind,
          'p_discount_value': discountValue,
          'p_discount_reason': discountReason,
        },
      );
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> settlePayment({
    required String arenaId,
    required String orderId,
    required String paymentId,
    required String method,
    required String amount,
    String? reference,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'order_settle',
        params: {
          'p_arena_id': arenaId,
          'p_order_id': orderId,
          'p_payment_id': paymentId,
          'p_payment_method': method,
          'p_amount': amount,
          'p_reference': reference,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }
}

final checkoutRepositoryProvider = Provider<CheckoutRepository>((ref) {
  return CheckoutRepository(ref.watch(supabaseClientProvider));
});
