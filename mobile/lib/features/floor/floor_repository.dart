import 'package:arena_os/app/bootstrap.dart';
import 'package:arena_os/core/errors/failure_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FloorRepository {
  FloorRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<Map<String, dynamic>> fetchFloorSnapshot(String arenaId) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'floor_snapshot',
        params: {'p_arena_id': arenaId},
      );
      if (response == null) {
        throw const FormatException('floor_snapshot returned null');
      }
      return Map<String, dynamic>.from(response as Map);
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> startSession({
    required String arenaId,
    required String sessionId,
    required String stationId,
    required String billingPlanId,
    String? memberId,
    String? gameId,
    int playerCount = 1,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'session_start',
        params: {
          'p_arena_id': arenaId,
          'p_session_id': sessionId,
          'p_station_id': stationId,
          'p_billing_plan_id': billingPlanId,
          'p_member_id': memberId,
          'p_game_id': gameId,
          'p_player_count': playerCount,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<void> pauseSession({
    required String arenaId,
    required String sessionId,
  }) async {
    try {
      await _supabase.rpc<dynamic>(
        'session_pause',
        params: {
          'p_arena_id': arenaId,
          'p_session_id': sessionId,
        },
      );
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<void> resumeSession({
    required String arenaId,
    required String sessionId,
  }) async {
    try {
      await _supabase.rpc<dynamic>(
        'session_resume',
        params: {
          'p_arena_id': arenaId,
          'p_session_id': sessionId,
        },
      );
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<void> stopSession({
    required String arenaId,
    required String sessionId,
  }) async {
    try {
      await _supabase.rpc<dynamic>(
        'session_stop',
        params: {
          'p_arena_id': arenaId,
          'p_session_id': sessionId,
        },
      );
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }
}

final floorRepositoryProvider = Provider<FloorRepository>((ref) {
  return FloorRepository(ref.watch(supabaseClientProvider));
});
