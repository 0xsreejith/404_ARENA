import 'dart:async';

import 'package:arena_os/features/lobby_ui/demo_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LobbyTab { floor, members, stock, more }

enum LobbyAuthMode { pin, email }

enum SessionSheetKind { session, bill }

class LobbyToast {
  const LobbyToast({required this.message, this.meta});

  final String message;
  final String? meta;
}

class AlertBubble {
  const AlertBubble({
    required this.stationId,
    required this.x,
    required this.y,
  });

  final String stationId;
  final double x;
  final double y;

  AlertBubble copyWith({double? x, double? y}) {
    return AlertBubble(
      stationId: stationId,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }
}

class LobbyBillPrefs {
  const LobbyBillPrefs({
    this.pay = 'cash',
    this.gst = false,
    this.coins = false,
  });

  final String pay;
  final bool gst;
  final bool coins;

  LobbyBillPrefs copyWith({String? pay, bool? gst, bool? coins}) {
    return LobbyBillPrefs(
      pay: pay ?? this.pay,
      gst: gst ?? this.gst,
      coins: coins ?? this.coins,
    );
  }
}

class LobbyUiState {
  const LobbyUiState({
    this.signedIn = false,
    this.selectedStaff,
    this.pin = '',
    this.pinError,
    this.tab = LobbyTab.floor,
    this.memberQuery = '',
    this.selectedMemberId,
    this.selectedStationId,
    this.sheetKind = SessionSheetKind.session,
    this.authMode = LobbyAuthMode.pin,
    this.authEmail = '',
    this.authPass = '',
    this.authError,
    this.soundOn = true,
    this.toast,
    this.clockLabel = '--:--',
    this.alertStationId,
    this.alertBubbles = const <AlertBubble>[],
    this.stationOverrides = const <String, DemoStation>{},
    this.ackedStationIds = const <String>{},
    this.snoozeUntil = const <String, DateTime>{},
    this.billPrefs = const LobbyBillPrefs(),
  });

  final bool signedIn;
  final DemoStaff? selectedStaff;
  final String pin;
  final String? pinError;
  final LobbyTab tab;
  final String memberQuery;
  final int? selectedMemberId;
  final String? selectedStationId;
  final SessionSheetKind sheetKind;
  final LobbyAuthMode authMode;
  final String authEmail;
  final String authPass;
  final String? authError;
  final bool soundOn;
  final LobbyToast? toast;
  final String clockLabel;
  final String? alertStationId;
  final List<AlertBubble> alertBubbles;
  final Map<String, DemoStation> stationOverrides;
  final Set<String> ackedStationIds;
  final Map<String, DateTime> snoozeUntil;
  final LobbyBillPrefs billPrefs;

  LobbyUiState copyWith({
    bool? signedIn,
    DemoStaff? selectedStaff,
    String? pin,
    String? pinError,
    LobbyTab? tab,
    String? memberQuery,
    int? selectedMemberId,
    String? selectedStationId,
    SessionSheetKind? sheetKind,
    LobbyAuthMode? authMode,
    String? authEmail,
    String? authPass,
    String? authError,
    bool? soundOn,
    LobbyToast? toast,
    String? clockLabel,
    String? alertStationId,
    List<AlertBubble>? alertBubbles,
    Map<String, DemoStation>? stationOverrides,
    Set<String>? ackedStationIds,
    Map<String, DateTime>? snoozeUntil,
    LobbyBillPrefs? billPrefs,
    bool clearMember = false,
    bool clearStation = false,
    bool clearPinError = false,
    bool clearAuthError = false,
    bool clearToast = false,
    bool clearStaff = false,
    bool clearAlert = false,
  }) {
    return LobbyUiState(
      signedIn: signedIn ?? this.signedIn,
      selectedStaff: clearStaff ? null : (selectedStaff ?? this.selectedStaff),
      pin: pin ?? this.pin,
      pinError: clearPinError ? null : (pinError ?? this.pinError),
      tab: tab ?? this.tab,
      memberQuery: memberQuery ?? this.memberQuery,
      selectedMemberId: clearMember ? null : (selectedMemberId ?? this.selectedMemberId),
      selectedStationId: clearStation ? null : (selectedStationId ?? this.selectedStationId),
      sheetKind: sheetKind ?? this.sheetKind,
      authMode: authMode ?? this.authMode,
      authEmail: authEmail ?? this.authEmail,
      authPass: authPass ?? this.authPass,
      authError: clearAuthError ? null : (authError ?? this.authError),
      soundOn: soundOn ?? this.soundOn,
      toast: clearToast ? null : (toast ?? this.toast),
      clockLabel: clockLabel ?? this.clockLabel,
      alertStationId: clearAlert ? null : (alertStationId ?? this.alertStationId),
      alertBubbles: alertBubbles ?? this.alertBubbles,
      stationOverrides: stationOverrides ?? this.stationOverrides,
      ackedStationIds: ackedStationIds ?? this.ackedStationIds,
      snoozeUntil: snoozeUntil ?? this.snoozeUntil,
      billPrefs: billPrefs ?? this.billPrefs,
    );
  }
}

class LobbyUiController extends Notifier<LobbyUiState> {
  Timer? _clock;
  Timer? _toastTimer;

  @override
  LobbyUiState build() {
    ref.onDispose(() {
      _clock?.cancel();
      _toastTimer?.cancel();
    });
    _startClock();
    return LobbyUiState(
      selectedStaff: _firstActiveStaff(),
      clockLabel: _formatClock(DateTime.now()),
    );
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(clockLabel: _formatClock(DateTime.now()));
      _checkAlerts();
    });
  }

  static String _formatClock(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static DemoStaff? _firstActiveStaff() {
    for (final s in DemoData.staff) {
      if (s.active) return s;
    }
    return null;
  }

  DemoStaff? get _effectiveStaff => state.selectedStaff ?? _firstActiveStaff();

  static DemoStation _base(String id) =>
      DemoData.stations.firstWhere((s) => s.id == id);

  DemoStation station(String id) => state.stationOverrides[id] ?? _base(id);

  void _updateStation(String id, DemoStation Function(DemoStation current) fn) {
    state = state.copyWith(
      stationOverrides: {...state.stationOverrides, id: fn(station(id))},
    );
  }

  void _checkAlerts() {
    if (!state.signedIn) return;
    if (state.alertStationId != null) return;
    if (state.selectedStationId != null) return;

    for (final base in DemoData.stations) {
      final s = station(base.id);
      if (state.ackedStationIds.contains(s.id)) continue;
      if (state.alertBubbles.any((b) => b.stationId == s.id)) continue;
      final snooze = state.snoozeUntil[s.id];
      if (snooze != null && DateTime.now().isBefore(snooze)) continue;

      final rem = s.remainingMinutes;
      if (s.isBusy && s.bookedMinutes != null && rem != null && rem <= 0) {
        state = state.copyWith(alertStationId: s.id);
        return;
      }
    }
  }

  void selectStaff(DemoStaff staff) {
    state = state.copyWith(selectedStaff: staff, pin: '', clearPinError: true);
  }

  void setAuthMode(LobbyAuthMode mode) {
    state = state.copyWith(
      authMode: mode,
      pin: '',
      clearPinError: true,
      clearAuthError: true,
    );
  }

  void setAuthEmail(String value) {
    state = state.copyWith(authEmail: value, clearAuthError: true);
  }

  void setAuthPass(String value) {
    state = state.copyWith(authPass: value, clearAuthError: true);
  }

  void emailSignIn() {
    if (state.authEmail.trim().isEmpty || state.authPass.isEmpty) {
      state = state.copyWith(authError: 'Enter email and password');
      return;
    }
    final staff = _effectiveStaff ?? DemoData.staff.first;
    state = state.copyWith(
      signedIn: true,
      selectedStaff: staff,
      authPass: '',
      clearAuthError: true,
      tab: LobbyTab.floor,
    );
    showToast('Signed in', staff.name);
    _checkAlerts();
  }

  void pressPin(String key) {
    final bound = _effectiveStaff;
    if (bound != null && state.selectedStaff == null) {
      state = state.copyWith(selectedStaff: bound);
    }

    if (key == 'del') {
      if (state.pin.isEmpty) return;
      state = state.copyWith(
        pin: state.pin.substring(0, state.pin.length - 1),
        clearPinError: true,
      );
      return;
    }
    if (key == 'ok') {
      _tryUnlock();
      return;
    }
    if (state.pin.length >= 4) return;
    final next = state.pin + key;
    state = state.copyWith(pin: next, clearPinError: true);
    if (next.length == 4) {
      Future<void>.delayed(const Duration(milliseconds: 160), _tryUnlock);
    }
  }

  void _tryUnlock() {
    final staff = _effectiveStaff;
    if (staff == null) return;
    if (state.pin.length != 4) return;
    if (state.pin != staff.pin) {
      state = state.copyWith(pin: '', pinError: 'Wrong PIN — try again');
      return;
    }
    state = state.copyWith(
      signedIn: true,
      selectedStaff: staff,
      pin: '',
      clearPinError: true,
      tab: LobbyTab.floor,
    );
    _checkAlerts();
  }

  void lock() {
    final keepSound = state.soundOn;
    state = LobbyUiState(
      selectedStaff: _firstActiveStaff(),
      soundOn: keepSound,
      clockLabel: _formatClock(DateTime.now()),
    );
  }

  void openSwitch() {
    lock();
    showToast('Switch profile', 'Enter the next staff PIN');
  }

  void toggleSound() {
    final next = !state.soundOn;
    state = state.copyWith(soundOn: next);
    showToast(
      next ? 'Sound cues on' : 'Sound cues muted',
      'Session start · time-up · 5-min warning',
    );
  }

  void switchMode() {
    showToast('Manage mode', 'Not wired in this pass');
  }

  void showToast(String message, [String? meta]) {
    _toastTimer?.cancel();
    state = state.copyWith(toast: LobbyToast(message: message, meta: meta));
    _toastTimer = Timer(const Duration(milliseconds: 2800), clearToast);
  }

  void clearToast() {
    state = state.copyWith(clearToast: true);
  }

  void setTab(LobbyTab tab) {
    state = state.copyWith(tab: tab, clearMember: true, clearStation: true);
  }

  void setMemberQuery(String q) {
    state = state.copyWith(memberQuery: q);
  }

  void openMember(int id) {
    state = state.copyWith(selectedMemberId: id);
  }

  void closeMember() {
    state = state.copyWith(clearMember: true);
  }

  void openStation(String id, {SessionSheetKind kind = SessionSheetKind.session}) {
    state = state.copyWith(
      selectedStationId: id,
      sheetKind: kind,
      billPrefs: kind == SessionSheetKind.bill ? const LobbyBillPrefs() : state.billPrefs,
    );
  }

  void closeStation() {
    state = state.copyWith(clearStation: true);
    _checkAlerts();
  }

  void showAlert(String id) {
    state = state.copyWith(
      alertStationId: id,
      alertBubbles: state.alertBubbles.where((b) => b.stationId != id).toList(),
    );
  }

  void minimizeAlert() {
    final id = state.alertStationId;
    if (id == null) return;
    final n = state.alertBubbles.length;
    state = state.copyWith(
      clearAlert: true,
      alertBubbles: [
        ...state.alertBubbles,
        AlertBubble(
          stationId: id,
          x: 940 - n * 16.0,
          y: 604 - n * 84.0,
        ),
      ],
    );
    showToast('$id parked as a bubble', 'Tap it when you are free');
  }

  void restoreAlert(String id) {
    state = state.copyWith(
      alertStationId: id,
      alertBubbles: state.alertBubbles.where((b) => b.stationId != id).toList(),
    );
  }

  void moveBubble(String id, double x, double y) {
    state = state.copyWith(
      alertBubbles: state.alertBubbles
          .map((b) => b.stationId == id ? b.copyWith(x: x, y: y) : b)
          .toList(),
    );
  }

  void dismissBubble(String id) {
    state = state.copyWith(
      ackedStationIds: {...state.ackedStationIds, id},
      alertBubbles: state.alertBubbles.where((b) => b.stationId != id).toList(),
    );
    showToast('$id left running', 'Overtime keeps billing · card on the floor stays red');
  }

  void extendAlert(int mins) {
    final id = state.alertStationId;
    if (id == null) return;
    final s = station(id);
    final booked = s.bookedMinutes ?? 0;
    _updateStation(
      id,
      (cur) => DemoStation(
        id: cur.id,
        type: cur.type,
        display: cur.display,
        zone: cur.zone,
        seats: cur.seats,
        ratePaise: cur.ratePaise,
        rateMode: cur.rateMode,
        status: DemoStationStatus.live,
        players: cur.players,
        game: cur.game,
        bookedMinutes: booked + mins,
        remainingMinutes: mins.toDouble(),
        elapsedMinutes: cur.elapsedMinutes,
      ),
    );
    final snooze = Map<String, DateTime>.from(state.snoozeUntil)..remove(id);
    state = state.copyWith(clearAlert: true, snoozeUntil: snooze);
    showToast('$id extended by $mins min', 'Clock restarted from where it stopped');
    _checkAlerts();
  }

  void snoozeAlert() {
    final id = state.alertStationId;
    if (id == null) return;
    state = state.copyWith(
      clearAlert: true,
      snoozeUntil: {
        ...state.snoozeUntil,
        id: DateTime.now().add(const Duration(minutes: 5)),
      },
    );
    showToast('$id snoozed 5 min', 'Alert will fire again soon');
  }

  void endAndBillFromAlert() {
    final id = state.alertStationId;
    if (id == null) return;
    state = state.copyWith(clearAlert: true);
    openStation(id, kind: SessionSheetKind.bill);
  }

  void toggleBillCoins() {
    final id = state.selectedStationId;
    if (id == null) return;
    final math = DemoData.billMath(station(id), gst: state.billPrefs.gst);
    if (math.maxCoin == 0) {
      showToast('No coins to redeem on this bill', 'Walk-in or zero balance');
      return;
    }
    state = state.copyWith(
      billPrefs: state.billPrefs.copyWith(coins: !state.billPrefs.coins),
    );
  }

  void toggleBillGst() {
    state = state.copyWith(
      billPrefs: state.billPrefs.copyWith(gst: !state.billPrefs.gst),
    );
  }

  void setBillPay(String pay) {
    state = state.copyWith(billPrefs: state.billPrefs.copyWith(pay: pay));
  }

  void confirmBill() {
    final id = state.selectedStationId;
    if (id == null) return;
    final pay = state.billPrefs.pay;
    final s = station(id);
    final math = DemoData.billMath(
      s,
      coins: state.billPrefs.coins,
      gst: state.billPrefs.gst,
    );
    _updateStation(
      id,
      (cur) => DemoStation(
        id: cur.id,
        type: cur.type,
        display: cur.display,
        zone: cur.zone,
        seats: cur.seats,
        ratePaise: cur.ratePaise,
        rateMode: cur.rateMode,
        status: DemoStationStatus.idle,
        players: const <String>[],
        game: null,
        bookedMinutes: null,
        remainingMinutes: null,
        elapsedMinutes: null,
      ),
    );
    state = state.copyWith(clearStation: true, billPrefs: const LobbyBillPrefs());
    showToast(
      'Paid · ${DemoData.inr(math.totalPaise)} collected',
      '${pay.toUpperCase()} · receipt printed',
    );
    _checkAlerts();
  }
}

final lobbyUiProvider = NotifierProvider<LobbyUiController, LobbyUiState>(LobbyUiController.new);
