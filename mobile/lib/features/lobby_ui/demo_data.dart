/// Demo seed matching `404 Lobby OS.dc.html` for pixel-parity UI review.
///
/// Names, stations, and displays live here (not in widgets) so the UI stays
/// tenant-agnostic when Supabase replaces this file in M2+.
library;

enum DemoStationStatus { idle, live, ending, overtime, maintenance, paused }

enum DemoStaffRole { staff, owner }

class DemoStation {
  const DemoStation({
    required this.id,
    required this.type,
    required this.display,
    required this.zone,
    required this.seats,
    required this.ratePaise,
    required this.status,
    this.rateMode,
    this.players = const <String>[],
    this.game,
    this.bookedMinutes,
    this.remainingMinutes,
    this.elapsedMinutes,
  });

  final String id;
  final String type;
  final String display;
  final String zone;
  final int seats;
  final int ratePaise;
  /// HTML `mode`: `'station'` | `'head'`.
  final String? rateMode;
  final DemoStationStatus status;
  final List<String> players;
  final String? game;
  final int? bookedMinutes;
  final double? remainingMinutes;
  final double? elapsedMinutes;

  /// `TYPE · ZONE · N SEATS · ₹/HR` [· PER HEAD] — matches HTML `typeLine`.
  String get typeLine {
    final seatWord = seats == 1 ? 'SEAT' : 'SEATS';
    final rate = '${DemoData.inr(ratePaise)}/HR';
    final head = rateMode == 'head' ? ' PER HEAD' : '';
    return '$type · $zone · $seats $seatWord · $rate$head';
  }

  /// Compact line for narrow station cards.
  String get typeShort => type.replaceFirst('PlayStation ', 'PS');

  bool get isBusy =>
      status == DemoStationStatus.live ||
      status == DemoStationStatus.ending ||
      status == DemoStationStatus.overtime ||
      status == DemoStationStatus.paused;

  bool get isPerHead => rateMode == 'head';

  /// Running bill in paise — mirrors HTML `amount(s, dd)`.
  int get runningAmountPaise {
    final heads = isPerHead ? (players.isEmpty ? 1 : players.length) : 1;
    final booked = bookedMinutes;
    if (booked == null) {
      final el = elapsedMinutes ?? 0;
      final blocks = (el / 15).ceil().clamp(1, 999999);
      return (blocks * ratePaise / 4 * heads).round();
    }
    var amt = (booked / 60.0) * ratePaise * heads;
    final rem = remainingMinutes;
    if (rem != null && rem < 0) {
      final overBlocks = ((-rem) / 15).ceil();
      amt += overBlocks * ratePaise / 4.0 * heads;
    }
    return amt.round();
  }
}

class DemoDisplay {
  const DemoDisplay({
    required this.id,
    required this.name,
    required this.type,
    required this.purpose,
  });

  final String id;
  final String name;
  final String type;
  final String purpose;
}

class DemoMember {
  const DemoMember({
    required this.id,
    required this.name,
    required this.phone,
    required this.plan,
    required this.visits,
    required this.spendPaise,
    required this.joined,
    this.coins = 0,
  });

  final int id;
  final String name;
  final String phone;
  final String plan;
  final int visits;
  final int spendPaise;
  final String joined;
  final int coins;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class DemoProduct {
  const DemoProduct({
    required this.name,
    required this.pricePaise,
    required this.stock,
    this.par = 14,
    this.soldToday = 0,
    this.soldWeek = 0,
  });

  final String name;
  final int pricePaise;
  final int stock;
  /// Reorder / par level from HTML `PAR`.
  final int par;
  final int soldToday;
  final int soldWeek;

  bool get isLow => stock > 0 && stock <= 10;
  bool get isNegative => stock < 0;
  bool get isBelowPar => stock <= par;
  bool get needsReorder => stock <= 10;

  String get flag {
    if (needsReorder) return 'REORDER';
    if (isBelowPar) return 'BELOW PAR';
    return 'OK';
  }
}

class DemoStaff {
  const DemoStaff({
    required this.id,
    required this.name,
    required this.role,
    required this.pin,
    required this.active,
  });

  final String id;
  final String name;
  final DemoStaffRole role;
  /// Demo-only credential. Never ship real PINs in source for production.
  final String pin;
  final bool active;

  String get roleLabel => switch (role) {
    DemoStaffRole.owner => 'OWNER',
    DemoStaffRole.staff => 'STAFF',
  };

  String get accessSummary => switch (role) {
    DemoStaffRole.owner => 'Full access',
    DemoStaffRole.staff => 'Sessions · checkout · members · shift',
  };

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class DemoShiftSnapshot {
  const DemoShiftSnapshot({
    required this.openedByStaffId,
    required this.openedAtLabel,
    required this.openingFloatPaise,
    required this.playSalesPaise,
    required this.productSalesPaise,
    required this.discountsPaise,
    required this.expectedCashPaise,
    required this.cashPaise,
    required this.upiPaise,
    required this.cardPaise,
  });

  final String openedByStaffId;
  final String openedAtLabel;
  final int openingFloatPaise;
  final int playSalesPaise;
  final int productSalesPaise;
  final int discountsPaise;
  final int expectedCashPaise;
  final int cashPaise;
  final int upiPaise;
  final int cardPaise;

  DemoStaff get openedBy => DemoData.staff.firstWhere((s) => s.id == openedByStaffId);
}

abstract final class DemoData {
  static const String arenaName = '404 Arena';
  static const String arenaMark = '404';
  static const String productName = 'LOBBY OS';
  static const String loginBlurbPin =
      'Pick your name, then your PIN. Whoever is picked here is who the shift is logged against.';
  static const String loginBlurbEmail =
      'Owner and manager accounts sign in with email. Counter staff use a PIN.';
  static const String loginBlurb = loginBlurbPin;

  /// HTML prototype collected takings (₹6,420).
  static const int collectedPaise = 642000;

  static const List<String> zoneOrder = <String>['PS ZONE', 'VR', 'POOL'];

  static int get liveCount => stations.where((s) => s.isBusy).length;

  static int get lowStockCount => products.where((p) => p.isLow).length;

  /// Approximate running floor bill (HTML `running()`).
  static int get runningFloorPaise {
    var total = 0;
    for (final s in stations) {
      if (!s.isBusy) continue;
      total += s.runningAmountPaise;
    }
    return total;
  }

  /// Real shop people. UI must read from this list — never hardcode names.
  static const List<DemoStaff> staff = <DemoStaff>[
    DemoStaff(
      id: 'staff_001',
      name: 'Sreejith',
      role: DemoStaffRole.staff,
      pin: '1234',
      active: true,
    ),
    DemoStaff(
      id: 'owner_001',
      name: 'Prashanth',
      role: DemoStaffRole.owner,
      pin: '1111',
      active: true,
    ),
    DemoStaff(
      id: 'owner_002',
      name: 'Anand',
      role: DemoStaffRole.owner,
      pin: '2222',
      active: true,
    ),
    DemoStaff(
      id: 'owner_003',
      name: 'Justin',
      role: DemoStaffRole.owner,
      pin: '3333',
      active: true,
    ),
  ];

  /// Lobby big monitor — sits above the PS5 bay in the shop layout.
  static const DemoDisplay lobbyDisplay = DemoDisplay(
    id: 'TV-01',
    name: 'Lobby Display',
    type: 'Big Monitor',
    purpose: 'Shows matches, announcements, and queue',
  );

  /// Floor seed from HTML prototype — mixed states for visual parity.
  static const List<DemoStation> stations = <DemoStation>[
    DemoStation(
      id: 'PS-01',
      type: 'PS5',
      display: 'Monitor',
      zone: 'PS ZONE',
      seats: 4,
      ratePaise: 12000,
      rateMode: 'station',
      status: DemoStationStatus.idle,
    ),
    DemoStation(
      id: 'PS-02',
      type: 'PS5',
      display: 'Monitor',
      zone: 'PS ZONE',
      seats: 4,
      ratePaise: 12000,
      rateMode: 'station',
      status: DemoStationStatus.ending,
      players: <String>['Arun Menon', 'Nikhil Raj'],
      game: 'EA FC 25',
      bookedMinutes: 60,
      remainingMinutes: 0.4,
    ),
    DemoStation(
      id: 'PS-03',
      type: 'PS4 Pro',
      display: 'Monitor',
      zone: 'PS ZONE',
      seats: 4,
      ratePaise: 10000,
      rateMode: 'station',
      status: DemoStationStatus.live,
      players: <String>['Sreya P', 'Kiran Das', 'Devika S'],
      game: 'Call of Duty MW3',
      elapsedMinutes: 52,
    ),
    DemoStation(
      id: 'PS-04',
      type: 'PS5',
      display: 'Monitor',
      zone: 'PS ZONE',
      seats: 2,
      ratePaise: 15000,
      rateMode: 'head',
      status: DemoStationStatus.ending,
      players: <String>['Hari Krishnan'],
      game: 'Tekken 8',
      bookedMinutes: 120,
      remainingMinutes: 4,
    ),
    DemoStation(
      id: 'VR-01',
      type: 'Quest 3',
      display: 'Headset',
      zone: 'VR',
      seats: 1,
      ratePaise: 25000,
      rateMode: 'station',
      status: DemoStationStatus.maintenance,
    ),
    DemoStation(
      id: 'POOL-01',
      type: '8-ball table',
      display: 'Table',
      zone: 'POOL',
      seats: 4,
      ratePaise: 20000,
      rateMode: 'station',
      status: DemoStationStatus.overtime,
      players: <String>['Kiran Das', 'Devika S'],
      game: '8-Ball',
      bookedMinutes: 30,
      remainingMinutes: -4,
    ),
  ];

  /// Sample members from HTML MEMBERS seed.
  static const List<DemoMember> members = <DemoMember>[
    DemoMember(
      id: 1,
      name: 'Arun Menon',
      phone: '+91 98470 41102',
      plan: 'MONTHLY',
      coins: 340,
      visits: 42,
      spendPaise: 1840000,
      joined: 'Mar 2025',
    ),
    DemoMember(
      id: 2,
      name: 'Nikhil Raj',
      phone: '+91 90480 77210',
      plan: 'MONTHLY',
      coins: 120,
      visits: 18,
      spendPaise: 620000,
      joined: 'Nov 2025',
    ),
    DemoMember(
      id: 3,
      name: 'Sreya P',
      phone: '+91 88910 30914',
      plan: 'QUARTERLY',
      coins: 710,
      visits: 61,
      spendPaise: 2735000,
      joined: 'Jan 2025',
    ),
    DemoMember(
      id: 4,
      name: 'Kiran Das',
      phone: '+91 76039 55018',
      plan: 'WALK-IN',
      coins: 0,
      visits: 5,
      spendPaise: 145000,
      joined: 'Jul 2026',
    ),
    DemoMember(
      id: 5,
      name: 'Hari Krishnan',
      phone: '+91 94470 18823',
      plan: 'MONTHLY',
      coins: 260,
      visits: 27,
      spendPaise: 910000,
      joined: 'Feb 2026',
    ),
    DemoMember(
      id: 6,
      name: 'Devika S',
      phone: '+91 85890 22140',
      plan: 'WALK-IN',
      coins: 0,
      visits: 9,
      spendPaise: 270000,
      joined: 'Jun 2026',
    ),
  ];

  /// Snack counter catalogue from HTML products seed.
  static const List<DemoProduct> products = <DemoProduct>[
    DemoProduct(name: 'Pepsi 500ml', pricePaise: 4000, stock: 24, soldToday: 18, soldWeek: 96),
    DemoProduct(name: 'Lays Magic Masala', pricePaise: 2000, stock: 31, soldToday: 11, soldWeek: 64),
    DemoProduct(name: 'Red Bull', pricePaise: 12500, stock: 8, soldToday: 26, soldWeek: 118),
    DemoProduct(name: 'Snickers', pricePaise: 4000, stock: 16, soldToday: 14, soldWeek: 72),
    DemoProduct(name: 'Water 1L', pricePaise: 2000, stock: 40, soldToday: 22, soldWeek: 130),
    DemoProduct(name: 'Maggi cup', pricePaise: 6000, stock: 12, soldToday: 19, soldWeek: 88),
  ];

  static const DemoShiftSnapshot shift = DemoShiftSnapshot(
    openedByStaffId: 'staff_001',
    openedAtLabel: '14:02',
    openingFloatPaise: 500000,
    playSalesPaise: 642000,
    productSalesPaise: 0,
    discountsPaise: 0,
    expectedCashPaise: 1142000,
    cashPaise: 500000,
    upiPaise: 642000,
    cardPaise: 0,
  );

  static DemoStaff? staffById(String id) {
    for (final s in staff) {
      if (s.id == id) return s;
    }
    return null;
  }

  static String inr(int paise) {
    final rupees = (paise / 100).round();
    final raw = rupees.toString();
    final withCommas = raw.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '₹$withCommas';
  }

  static String formatDuration(double minutes) {
    final abs = minutes.abs();
    final m = abs.floor();
    final s = ((abs - m) * 60).round().clamp(0, 59);
    final body = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return minutes < 0 ? '+$body' : body;
  }

  /// Bill sheet line item — mirrors HTML `billMath` lines.
  static List<DemoBillLine> billLines(DemoStation s) {
    final heads = s.isPerHead ? (s.players.isEmpty ? 1 : s.players.length) : 1;
    final sessionAmt = s.runningAmountPaise;
    final booked = s.bookedMinutes;
    final base = booked != null
        ? (booked / 60.0 * s.ratePaise * heads).round()
        : sessionAmt;
    final rateHr = '${inr(s.ratePaise)}/hr';
    final mode = s.isPerHead ? '× $heads heads' : 'per station';
    final lines = <DemoBillLine>[
      DemoBillLine(
        name: booked != null ? '$booked min on ${s.id}' : 'Open time on ${s.id}',
        detail: '${s.type} · $rateHr $mode · ${s.game ?? ''}',
        qty: booked != null ? '1' : '${((s.elapsedMinutes ?? 15) / 15).ceil().clamp(1, 999)}×15m',
        amountPaise: base,
      ),
    ];
    final rem = s.remainingMinutes;
    if (booked != null && rem != null && rem < 0) {
      lines.add(
        DemoBillLine(
          name: 'Over time',
          detail: '${formatDuration(rem)} past the booked hour · billed per 15 min',
          qty: '${((-rem) / 15).ceil()}×15m',
          amountPaise: sessionAmt - base,
          warn: true,
        ),
      );
    }
    return lines;
  }

  /// Bill totals — mirrors HTML `billMath` return value.
  static DemoBillMath billMath(
    DemoStation s, {
    bool coins = false,
    bool gst = false,
  }) {
    final lines = billLines(s);
    final sub = lines.fold<int>(0, (a, l) => a + l.amountPaise);
    DemoMember? mem;
    if (s.players.isNotEmpty) {
      for (final m in members) {
        if (m.name == s.players.first) {
          mem = m;
          break;
        }
      }
    }
    final maxCoin = mem != null
        ? (mem.coins < sub ~/ 400 ? mem.coins : sub ~/ 400)
        : 0;
    final coinCut = coins && maxCoin > 0 ? maxCoin * 100 : 0;
    final taxable = sub - coinCut;
    final gstAmt = gst ? (taxable * 0.18).round() : 0;
    return DemoBillMath(
      lines: lines,
      subPaise: sub,
      coinCutPaise: coinCut,
      maxCoin: maxCoin,
      gstPaise: gstAmt,
      totalPaise: taxable + gstAmt,
      member: mem,
    );
  }
}

class DemoBillLine {
  const DemoBillLine({
    required this.name,
    required this.detail,
    required this.qty,
    required this.amountPaise,
    this.warn = false,
  });

  final String name;
  final String detail;
  final String qty;
  final int amountPaise;
  final bool warn;
}

class DemoBillMath {
  const DemoBillMath({
    required this.lines,
    required this.subPaise,
    required this.coinCutPaise,
    required this.maxCoin,
    required this.gstPaise,
    required this.totalPaise,
    this.member,
  });

  final List<DemoBillLine> lines;
  final int subPaise;
  final int coinCutPaise;
  final int maxCoin;
  final int gstPaise;
  final int totalPaise;
  final DemoMember? member;
}
