import 'dart:io' show Platform;
import 'dart:math';

import 'package:arena_os/app/bootstrap.dart';
import 'package:arena_os/core/errors/failure_mapper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists a stable device UUID and registers it with `register_device`.
class DeviceRepository {
  DeviceRepository(this._supabase);

  final SupabaseClient _supabase;
  static const _prefsKey = 'arena_os.device_id';

  Future<String> loadOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final id = _newUuidV4();
    await prefs.setString(_prefsKey, id);
    return id;
  }

  Future<void> register({
    required String arenaId,
    required String deviceName,
    String? appVersion,
  }) async {
    final deviceId = await loadOrCreateDeviceId();
    try {
      await _supabase.rpc<dynamic>(
        'register_device',
        params: <String, dynamic>{
          'p_arena_id': arenaId,
          'p_device_id': deviceId,
          'p_name': deviceName,
          'p_platform': _platformWireName(),
          'p_app_version': appVersion,
        },
      );
    } catch (error, stackTrace) {
      throw failureMapper.map(error, stackTrace);
    }
  }

  static String _platformWireName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'desktop';
  }

  static String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(ref.watch(supabaseClientProvider));
});

/// Last successful server contact (me / floor). Used for D18 stale gate.
final lastServerContactProvider = NotifierProvider<LastServerContactNotifier, DateTime?>(
  LastServerContactNotifier.new,
);

class LastServerContactNotifier extends Notifier<DateTime?> {
  static const staleAfter = Duration(hours: 24);

  @override
  DateTime? build() => null;

  void touch() => state = DateTime.now().toUtc();

  bool get isStale {
    final last = state;
    if (last == null) return false;
    return DateTime.now().toUtc().difference(last) > staleAfter;
  }
}
