import 'package:arena_os/app/bootstrap.dart';
import 'package:arena_os/core/errors/failure_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MembersRepository {
  MembersRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<Map<String, dynamic>>> search({
    required String arenaId,
    required String query,
    int limit = 20,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'member_search',
        params: {
          'p_arena_id': arenaId,
          'p_query': query,
          'p_limit': limit,
        },
      );
      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      final members = map['members'];
      if (members is! List) return const [];
      return members
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> get({
    required String arenaId,
    required String memberId,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'member_get',
        params: {
          'p_arena_id': arenaId,
          'p_member_id': memberId,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> create({
    required String arenaId,
    required String memberId,
    required String fullName,
    required String phone,
    String? notes,
    String? idempotencyKey,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'member_create',
        params: {
          'p_arena_id': arenaId,
          'p_member_id': memberId,
          'p_full_name': fullName,
          'p_phone': phone,
          'p_dob': null,
          'p_notes': notes,
          'p_idempotency_key': idempotencyKey,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> update({
    required String arenaId,
    required String memberId,
    String? fullName,
    String? phone,
    String? notes,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'member_update',
        params: {
          'p_arena_id': arenaId,
          'p_member_id': memberId,
          'p_full_name': fullName,
          'p_phone': phone,
          'p_dob': null,
          'p_notes': notes,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> setBlocked({
    required String arenaId,
    required String memberId,
    required bool blocked,
    String? reason,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'member_set_blocked',
        params: {
          'p_arena_id': arenaId,
          'p_member_id': memberId,
          'p_blocked': blocked,
          'p_reason': reason,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<List<Map<String, dynamic>>> timeline({
    required String arenaId,
    required String memberId,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'member_timeline',
        params: {
          'p_arena_id': arenaId,
          'p_member_id': memberId,
          'p_limit': 50,
        },
      );
      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      final events = map['events'];
      if (events is! List) return const [];
      return events
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<List<Map<String, dynamic>>> listNotes({
    required String arenaId,
    required String memberId,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'member_note_list',
        params: {
          'p_arena_id': arenaId,
          'p_member_id': memberId,
        },
      );
      final map = Map<String, dynamic>.from(response as Map? ?? const {});
      final notes = map['notes'];
      if (notes is! List) return const [];
      return notes
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> addNote({
    required String arenaId,
    required String memberId,
    required String kind,
    required String body,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'member_note_add',
        params: {
          'p_arena_id': arenaId,
          'p_member_id': memberId,
          'p_kind': kind,
          'p_body': body,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  Future<Map<String, dynamic>> walletHistory({
    required String arenaId,
    required String memberId,
  }) async {
    try {
      final response = await _supabase.rpc<dynamic>(
        'wallet_history',
        params: {
          'p_arena_id': arenaId,
          'p_member_id': memberId,
          'p_limit': 50,
        },
      );
      return Map<String, dynamic>.from(response as Map? ?? const {});
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }
}

final membersRepositoryProvider = Provider<MembersRepository>((ref) {
  return MembersRepository(ref.watch(supabaseClientProvider));
});
