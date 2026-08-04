import 'package:arena_os/app/bootstrap.dart';
import 'package:arena_os/core/errors/failure_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShiftRepository {
  ShiftRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<Map<String, dynamic>?> fetchCurrent(String arenaId) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'shift_current',
        params: {'p_arena_id': arenaId},
      );
      if (response == null) return null;
      return Map<String, dynamic>.from(response as Map);
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> openShift({
    required String arenaId,
    required String shiftId,
    required String openingFloat,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'shift_open',
        params: {
          'p_arena_id': arenaId,
          'p_shift_id': shiftId,
          'p_opening_float': openingFloat,
          'p_idempotency_key': idempotencyKey,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> fetchSummary({
    required String arenaId,
    required String shiftId,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'shift_summary',
        params: {
          'p_arena_id': arenaId,
          'p_shift_id': shiftId,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> closeShift({
    required String arenaId,
    required String shiftId,
    required String countedCash,
    required String notes,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'shift_close',
        params: {
          'p_arena_id': arenaId,
          'p_shift_id': shiftId,
          'p_counted_cash': countedCash,
          'p_notes': notes,
          'p_idempotency_key': idempotencyKey,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }
}

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  return ShiftRepository(ref.watch(supabaseClientProvider));
});
