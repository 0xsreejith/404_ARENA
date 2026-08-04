import { DateRange, RANGE_MUL, inr, type OwnerTokens } from '../theme/tokens';

/** Prototype fixture data for Owner Web screens lacking report/member RPCs. */

export const FIXTURE_MEMBERS = [
  { id: 'm1', name: 'Arjun K', phone: '98765 43210', plan: 'GOLD', visits: 42, spend: 18400, coins: 120, last: 'Today', blocked: false, expDays: 4, joined: '12 Jan 25' },
  { id: 'm2', name: 'Sreya P', phone: '98470 11223', plan: 'SILVER', visits: 28, spend: 9200, coins: 40, last: 'Yesterday', blocked: false, expDays: 6, joined: '03 Mar 25' },
  { id: 'm3', name: 'Kiran Das', phone: '98950 77881', plan: 'WALK-IN', visits: 9, spend: 3100, coins: 0, last: '2 days', blocked: false, expDays: null as number | null, joined: '18 Jun 25' },
  { id: 'm4', name: 'Devika S', phone: '97460 33445', plan: 'GOLD', visits: 61, spend: 24100, coins: 210, last: 'Today', blocked: false, expDays: 12, joined: '22 Nov 24' },
  { id: 'm5', name: 'Rahul M', phone: '99955 22110', plan: 'SILVER', visits: 15, spend: 4800, coins: 15, last: '5 days', blocked: true, expDays: 2, joined: '09 Apr 25' },
  { id: 'm6', name: 'Anjali V', phone: '95670 88990', plan: 'WALK-IN', visits: 3, spend: 900, coins: 0, last: '12 days', blocked: false, expDays: null, joined: '01 Jul 25' },
  { id: 'm7', name: 'Nikhil R', phone: '96330 44556', plan: 'GOLD', visits: 37, spend: 15200, coins: 88, last: 'Yesterday', blocked: false, expDays: 19, joined: '14 Feb 25' },
  { id: 'm8', name: 'Meera T', phone: '97440 66778', plan: 'SILVER', visits: 22, spend: 7100, coins: 30, last: '3 days', blocked: false, expDays: 5, joined: '28 May 25' },
];

export const FIXTURE_GAMES = [
  { t: 'EA FC 25', r: '3+', plat: 'PS5', on: ['PS-01', 'PS-02', 'PS-03', 'PS-04'], hrs: 46 },
  { t: 'Call of Duty MW3', r: '18+', plat: 'PS4 / PS5', on: ['PS-02', 'PS-03', 'PS-04'], hrs: 38 },
  { t: 'Tekken 8', r: '16+', plat: 'PS5', on: ['PS-01', 'PS-05'], hrs: 22 },
  { t: 'Mortal Kombat 1', r: '18+', plat: 'PS5', on: ['PS-03'], hrs: 18 },
  { t: 'GTA V', r: '18+', plat: 'PS5', on: ['PS-01', 'PS-02'], hrs: 31 },
  { t: 'Beat Saber', r: '3+', plat: 'VR', on: ['VR-01'], hrs: 27 },
  { t: '8-Ball', r: '3+', plat: 'Pool', on: ['POOL-01'], hrs: 19 },
];

export const FIXTURE_PRODUCTS = [
  { name: 'Cola 330ml', stock: 8, par: 24, sold: '41 this week', low: true },
  { name: 'Crisps salted', stock: 5, par: 20, sold: '33 this week', low: true },
  { name: 'Energy drink', stock: 14, par: 18, sold: '19 this week', low: true },
  { name: 'Water 500ml', stock: 48, par: 36, sold: '62 this week', low: false },
  { name: 'Chocolate bar', stock: 22, par: 16, sold: '28 this week', low: false },
];

export const FIXTURE_SESSIONS = [
  ['19:42', 'PS-02', 'Arjun K · Sreya P', 'EA FC 25', '58 min', 480, 'UPI', 'paid'],
  ['19:10', 'PS-03', 'Kiran Das · Devika S · Guest', 'Call of Duty MW3', '95 min', 190, 'CASH', 'paid'],
  ['18:21', 'VR-01', 'Rahul M', 'Beat Saber', '30 min', 300, 'CARD', 'paid'],
  ['17:05', 'POOL-01', 'Walk-in ×2', '8-Ball', '45 min', 150, 'CASH', 'paid'],
  ['16:40', 'PS-01', 'Nikhil R', 'GTA V', '120 min', 720, 'UPI', 'paid'],
  ['15:12', 'PS-04', 'Meera T', 'Tekken 8', '60 min', 360, 'UPI', 'live'],
  ['14:00', 'PS-05', 'Anjali V', 'EA FC 25', '40 min', 240, '—', 'refund'],
] as const;

export const FIXTURE_PLANS = [
  { name: 'GOLD', price: 2499, term: 'month', perks: '15% off play · priority booking · 200 coins', active: true, holders: 34 },
  { name: 'SILVER', price: 999, term: 'month', perks: '8% off play · 50 coins', active: true, holders: 51 },
  { name: 'DAY PASS', price: 399, term: 'day', perks: 'Open play until close · no coins', active: false, holders: 0 },
];

export const FIXTURE_STAFF = [
  { name: 'Prasanth', role: 'OWNER', pin: '••••', active: true },
  { name: 'Anjali K', role: 'MANAGER', pin: '••••', active: true },
  { name: 'Ravi', role: 'STAFF', pin: '••••', active: true },
  { name: 'Neha', role: 'STAFF', pin: '••••', active: false },
];

export const FIXTURE_EXPENSES = [
  { date: '27 Jul', cat: 'Utilities', note: 'Electricity — July', amt: 8400, mode: 'UPI', bill: true },
  { date: '26 Jul', cat: 'Supplies', note: 'Snack restock (Cola + crisps)', amt: 3200, mode: 'CASH', bill: true },
  { date: '24 Jul', cat: 'Maintenance', note: 'PS-05 HDMI cable', amt: 450, mode: 'CASH', bill: false },
  { date: '22 Jul', cat: 'Rent', note: 'Shop rent — July', amt: 45000, mode: 'BANK', bill: true },
];

export const FIXTURE_INTEGRATIONS = [
  ['razorpay', 'Razorpay', 'Cards and netbanking on the counter tablet', 'MDR 2% · settles T+2', true],
  ['upi', 'UPI QR', 'Dynamic QR on each bill', 'Instant · 0 MDR on UPI', true],
  ['whatsapp', 'WhatsApp receipts', 'Send receipt link after settle', 'Meta Cloud API', false],
  ['printer', 'Thermal printer', '58mm receipt printer on counter', 'USB · ESC/POS', true],
] as const;

export const FIXTURE_VISITS = [
  { date: '26 Jul', station: 'PS-02', title: 'EA FC 25', length: '60 min', amount: '₹480' },
  { date: '21 Jul', station: 'PS-01', title: 'Mortal Kombat 1', length: '90 min', amount: '₹540' },
  { date: '18 Jul', station: 'VR-01', title: 'Beat Saber', length: '30 min', amount: '₹300' },
  { date: '14 Jul', station: 'PS-03', title: 'EA FC 25', length: '120 min', amount: '₹720' },
  { date: '09 Jul', station: 'POOL-01', title: '8-Ball', length: '45 min', amount: '₹150' },
];

export function initials(name: string): string {
  return name
    .split(/\s+/)
    .map((p) => p[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}

export function expiringMembers() {
  return FIXTURE_MEMBERS.filter((m) => m.expDays != null && m.expDays <= 7 && !m.blocked);
}

export function lowStockProducts() {
  return FIXTURE_PRODUCTS.filter((p) => p.low);
}

export function dashboardKpis(range: DateRange, T: OwnerTokens, staffName: string) {
  const mul = RANGE_MUL[range];
  const rangeWord =
    range === 'today' ? 'today' : range === 'week' ? 'this week' : range === 'month' ? 'this month' : 'last 90 days';
  const base = 4120 * mul;
  return [
    {
      label: 'Collection',
      value: inr(base),
      delta: '+12%',
      sub: `${rangeWord} · ${Math.round(14 * mul)} sessions`,
      deltaBg: T.posTint,
      deltaFg: T.posInk3,
    },
    {
      label: 'Seat utilisation',
      value: '61%',
      delta: '+4pt',
      sub: 'Peak 20:00 at 92%',
      deltaBg: T.posTint,
      deltaFg: T.posInk3,
    },
    {
      label: 'Active memberships',
      value: String(FIXTURE_MEMBERS.filter((m) => m.plan !== 'WALK-IN' && !m.blocked).length),
      delta: '−2',
      sub: `${expiringMembers().length} lapse within 7 days`,
      deltaBg: T.warnTint,
      deltaFg: T.warn,
    },
    {
      label: 'Average spend',
      value: inr(458),
      delta: '+₹31',
      sub: `Snacks attach on 44% of bills · ${staffName}`,
      deltaBg: T.posTint,
      deltaFg: T.posInk3,
    },
  ];
}

export function hourlyBars(T: OwnerTokens) {
  const hours = ['12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '00'];
  const heights = [22, 28, 35, 40, 48, 55, 70, 88, 100, 92, 75, 50, 30];
  return hours.map((hour, i) => {
    const h = heights[i];
    const snack = Math.max(8, Math.round(h * 0.22));
    const peak = hour === '20';
    return {
      hour,
      amt: inr(180 + h * 18),
      h: `${h}%`,
      snackH: `${snack}%`,
      fill: peak ? T.accent : T.chart2,
      rad: snack > 0 ? '0' : '4px 4px 0 0',
    };
  });
}

export function dailyBars(T: OwnerTokens) {
  const days = ['14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27'];
  const vals = [42, 55, 48, 61, 70, 88, 95, 72, 66, 80, 74, 91, 85, 78];
  return days.map((day, i) => ({
    day,
    amt: inr(vals[i] * 120),
    h: `${vals[i]}%`,
    fill: i === days.length - 1 ? T.accent : T.chart4,
  }));
}

export function heatRows(T: OwnerTokens) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const heatHours = ['11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23'];
  return {
    heatHours: heatHours.map((label) => ({ label })),
    heatRows: days.map((day, di) => ({
      day,
      cells: heatHours.map((_, hi) => {
        const v = Math.min(99, Math.max(4, ((di * 13 + hi * 7) % 40) + (hi > 7 ? 35 : 5)));
        const a = (v / 100) * 0.85;
        return {
          v: String(v),
          bg: `rgba(${T.heatRgb},${a.toFixed(2)})`,
          fg: v > 55 ? '#fff' : T.ink3,
        };
      }),
    })),
  };
}

export function payMix(T: OwnerTokens) {
  return [
    { label: 'UPI', amt: inr(24800), pct: '52%', fill: T.accent },
    { label: 'Cash', amt: inr(14200), pct: '30%', fill: T.pos },
    { label: 'Card', amt: inr(6800), pct: '14%', fill: T.chart2 },
    { label: 'Pay later', amt: inr(1900), pct: '4%', fill: T.warn },
  ];
}

export function zoneRows(T: OwnerTokens) {
  return [
    { zone: 'PS zone', hours: '84 h', amt: inr(41200), util: '68%', utilFg: T.posInk3 },
    { zone: 'VR', hours: '22 h', amt: inr(11800), util: '41%', utilFg: T.warn },
    { zone: 'Pool', hours: '38 h', amt: inr(9600), util: '57%', utilFg: T.posInk3 },
  ];
}
