import React, { useEffect, useMemo, useState } from 'react';
import { useOwnerNav } from '../../components/owner/OwnerShell';
import { useAuth } from '../../context/AuthContext';
import {
  FIXTURE_EXPENSES,
  FIXTURE_GAMES,
  FIXTURE_INTEGRATIONS,
  FIXTURE_PRODUCTS,
  FIXTURE_SESSIONS,
  FIXTURE_STAFF,
  dailyBars,
  heatRows,
  initials,
  payMix,
  zoneRows,
} from '../../data/ownerFixtures';
import {
  createMember,
  fetchMemberAnalytics,
  getMember,
  listMembershipPlans,
  MemberRecord,
  MemberSearchRow,
  readableMemberError,
  searchMembers,
  setMemberBlocked,
  walletTopup,
} from '../../services/members';
import { inr } from '../../theme/tokens';

export const ReportsPage: React.FC = () => {
  const { T, range } = useOwnerNav();
  const [tab, setTab] = useState<'revenue' | 'util' | 'titles' | 'members' | 'staff'>('revenue');
  const heat = useMemo(() => heatRows(T), [T]);
  const days = useMemo(() => dailyBars(T), [T]);
  const pays = useMemo(() => payMix(T), [T]);
  const zones = useMemo(() => zoneRows(T), [T]);

  const tiles = [
    { label: 'Gross collection', value: inr(4120 * (range === 'today' ? 1 : 6.4)), sub: 'Sessions + snacks', fg: T.ink },
    { label: 'Sessions closed', value: '14', sub: 'Avg 68 min', fg: T.ink },
    { label: 'Snack attach', value: '44%', sub: 'Of settled bills', fg: T.posInk3 },
    { label: 'Unbilled', value: '1', sub: 'Chase before close', fg: T.warn },
  ];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
      <div className="ow-tabs">
        {(
          [
            ['revenue', 'Revenue'],
            ['util', 'Utilisation'],
            ['titles', 'Titles'],
            ['members', 'Members'],
            ['staff', 'Staff'],
          ] as const
        ).map(([id, label]) => (
          <button key={id} type="button" className={`ow-tab${tab === id ? ' is-active' : ''}`} onClick={() => setTab(id)}>
            {label}
          </button>
        ))}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 14 }}>
        {tiles.map((k) => (
          <div key={k.label} className="ow-kpi" style={{ gap: 6 }}>
            <span className="ow-kpi-label">{k.label}</span>
            <span className="ow-kpi-value" style={{ fontSize: 25, color: k.fg }}>
              {k.value}
            </span>
            <span className="ow-kpi-sub">{k.sub}</span>
          </div>
        ))}
      </div>

      {tab === 'revenue' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div className="ow-panel" style={{ padding: '18px 20px 14px' }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 16 }}>
              <span style={{ fontWeight: 700, fontSize: 15 }}>Collection by day</span>
              <span style={{ fontSize: 12, color: 'var(--ow-faint)' }}>sessions and snacks</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'flex-end', gap: 10, height: 180 }}>
              {days.map((d) => (
                <div
                  key={d.day}
                  style={{
                    flex: 1,
                    display: 'flex',
                    flexDirection: 'column',
                    justifyContent: 'flex-end',
                    alignItems: 'center',
                    gap: 7,
                    height: '100%',
                  }}
                >
                  <span className="ow-mono" style={{ fontSize: 9.5, color: 'var(--ow-faint)' }}>
                    {d.amt}
                  </span>
                  <div style={{ width: '100%', borderRadius: '5px 5px 0 0', height: d.h, background: d.fill }} />
                  <span className="ow-mono" style={{ fontSize: 9.5, color: 'var(--ow-muted)' }}>
                    {d.day}
                  </span>
                </div>
              ))}
            </div>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
            <div className="ow-panel">
              <span style={{ fontWeight: 700, fontSize: 15 }}>How people paid</span>
              {pays.map((p) => (
                <div key={p.label} style={{ padding: '12px 0', borderTop: '1px solid var(--ow-hair)', marginTop: 8, display: 'flex', flexDirection: 'column', gap: 7 }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 9 }}>
                    <span style={{ fontSize: 13.5, fontWeight: 600, flex: 1 }}>{p.label}</span>
                    <span className="ow-mono" style={{ fontSize: 13, fontWeight: 700 }}>
                      {p.amt}
                    </span>
                    <span className="ow-mono" style={{ fontSize: 11, color: 'var(--ow-faint)', width: 38, textAlign: 'right' }}>
                      {p.pct}
                    </span>
                  </div>
                  <div style={{ height: 7, borderRadius: 4, background: 'var(--ow-chip)', overflow: 'hidden' }}>
                    <div style={{ height: '100%', borderRadius: 4, width: p.pct, background: p.fill }} />
                  </div>
                </div>
              ))}
            </div>
            <div className="ow-panel">
              <span style={{ fontWeight: 700, fontSize: 15 }}>Revenue by zone</span>
              <div
                style={{
                  display: 'grid',
                  gridTemplateColumns: '1fr 92px 92px 78px',
                  gap: 10,
                  padding: '12px 0 8px',
                  marginTop: 6,
                  borderBottom: '1px solid var(--ow-hair)',
                }}
              >
                {['ZONE', 'HOURS', 'AMOUNT', 'UTIL'].map((c, i) => (
                  <span key={c} className="ow-mono" style={{ fontSize: 9.5, letterSpacing: '0.1em', color: 'var(--ow-faint)', textAlign: i ? 'right' : 'left' }}>
                    {c}
                  </span>
                ))}
              </div>
              {zones.map((z) => (
                <div
                  key={z.zone}
                  style={{
                    display: 'grid',
                    gridTemplateColumns: '1fr 92px 92px 78px',
                    gap: 10,
                    padding: '12px 0',
                    borderBottom: '1px solid var(--ow-canvas)',
                    alignItems: 'center',
                  }}
                >
                  <span style={{ fontSize: 13.5, fontWeight: 600 }}>{z.zone}</span>
                  <span className="ow-mono" style={{ fontSize: 13, textAlign: 'right' }}>
                    {z.hours}
                  </span>
                  <span className="ow-mono" style={{ fontSize: 13, fontWeight: 700, textAlign: 'right' }}>
                    {z.amt}
                  </span>
                  <span className="ow-mono" style={{ fontSize: 12, textAlign: 'right', color: z.utilFg }}>
                    {z.util}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {tab === 'util' && (
        <div className="ow-panel">
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 14 }}>
            <span style={{ fontWeight: 700, fontSize: 15 }}>Seat utilisation · weekday by hour</span>
            <span style={{ fontSize: 12, color: 'var(--ow-faint)' }}>Darker means fuller.</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <div style={{ display: 'grid', gridTemplateColumns: '52px repeat(13, 1fr)', gap: 4 }}>
              <span />
              {heat.heatHours.map((h) => (
                <span key={h.label} className="ow-mono" style={{ fontSize: 9.5, color: 'var(--ow-faint)', textAlign: 'center' }}>
                  {h.label}
                </span>
              ))}
            </div>
            {heat.heatRows.map((r) => (
              <div key={r.day} style={{ display: 'grid', gridTemplateColumns: '52px repeat(13, 1fr)', gap: 4, alignItems: 'center' }}>
                <span className="ow-mono" style={{ fontSize: 10.5, color: 'var(--ow-ink3)' }}>
                  {r.day}
                </span>
                {r.cells.map((c, i) => (
                  <span
                    key={i}
                    style={{
                      height: 26,
                      borderRadius: 5,
                      background: c.bg,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontFamily: 'var(--font-mono)',
                      fontSize: 9,
                      color: c.fg,
                    }}
                  >
                    {c.v}
                  </span>
                ))}
              </div>
            ))}
          </div>
        </div>
      )}

      {tab === 'titles' && (
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
          <div className="ow-panel">
            <span style={{ fontWeight: 700, fontSize: 15 }}>Hours by title</span>
            {FIXTURE_GAMES.slice()
              .sort((a, b) => b.hrs - a.hrs)
              .slice(0, 6)
              .map((g) => (
                <div key={g.t} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '12px 0', borderTop: '1px solid var(--ow-hair)', marginTop: 6 }}>
                  <span style={{ fontSize: 13.5, fontWeight: 600, flex: 1 }}>{g.t}</span>
                  <span className="ow-mono" style={{ fontSize: 12, color: 'var(--ow-faint)' }}>
                    {g.hrs} h
                  </span>
                  <div style={{ width: 120, height: 7, borderRadius: 4, background: 'var(--ow-chip)' }}>
                    <div style={{ width: `${(g.hrs / 46) * 100}%`, height: '100%', borderRadius: 4, background: 'var(--ow-accent)' }} />
                  </div>
                </div>
              ))}
          </div>
          <div className="ow-panel">
            <span style={{ fontWeight: 700, fontSize: 15 }}>Catalogue notes</span>
            {[
              { title: 'EA FC 25', badge: 'BUY 2 MORE', bg: T.accTint, fg: T.accInk, note: 'Requested on idle stations eleven times this month.' },
              { title: 'Beat Saber', badge: 'VR DRIVER', bg: T.posTint, fg: T.posInk3, note: 'Three quarters of VR sessions start with this title.' },
              { title: 'Tekken 8', badge: 'WATCH', bg: T.warnTint, fg: T.warn, note: 'Hours halved since the FC 25 season started.' },
            ].map((n) => (
              <div key={n.title} style={{ padding: '12px 0', borderTop: '1px solid var(--ow-hair)', marginTop: 8 }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 9, marginBottom: 6 }}>
                  <span style={{ fontWeight: 700, fontSize: 14 }}>{n.title}</span>
                  <span className="ow-chip" style={{ background: n.bg, color: n.fg }}>
                    {n.badge}
                  </span>
                </div>
                <span style={{ fontSize: 12.5, color: 'var(--ow-muted)' }}>{n.note}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {(tab === 'members' || tab === 'staff') && (
        <div className="ow-panel">
          <span style={{ fontWeight: 700, fontSize: 15 }}>{tab === 'members' ? 'Member cohort' : 'Staff on shift'}</span>
          <p style={{ marginTop: 12, fontSize: 13.5, color: 'var(--ow-muted)', maxWidth: 560 }}>
            {tab === 'members'
              ? 'Use Members / Memberships screens for live CRM analytics (member_analytics_overview). This reports tab remains a layout placeholder for cohort charts.'
              : 'Hours worked and cash handled will bind to shift summary RPCs. Layout matches W2 Staff tab.'}
          </p>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12, marginTop: 16 }}>
            {(tab === 'members'
              ? [
                  ['New this month', '12'],
                  ['Returning', '68%'],
                  ['Blocked', '1'],
                ]
              : [
                  ['Shifts closed', '22'],
                  ['Cash variance', '₹40'],
                  ['Staff online', '2'],
                ]
            ).map(([l, v]) => (
              <div key={l} style={{ padding: 14, borderRadius: 10, background: 'var(--ow-canvas)', border: '1px solid var(--ow-bd)' }}>
                <div style={{ fontSize: 12, color: 'var(--ow-muted)' }}>{l}</div>
                <div className="ow-mono" style={{ fontWeight: 700, fontSize: 22, marginTop: 4 }}>
                  {v}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

export const SessionsPage: React.FC = () => {
  const { T } = useOwnerNav();
  const [filter, setFilter] = useState('all');
  const filters = [
    ['all', 'All'],
    ['live', 'Live'],
    ['paid', 'Paid'],
    ['refund', 'Refund'],
  ] as const;

  const rows = FIXTURE_SESSIONS.filter((r) => filter === 'all' || r[7] === filter);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ display: 'flex', gap: 8 }}>
        {filters.map(([id, label]) => (
          <button
            key={id}
            type="button"
            className="ow-btn"
            style={{
              background: filter === id ? T.accTint : T.panel,
              color: filter === id ? T.accInk : T.ink2b,
              border: `1px solid ${filter === id ? T.accBd : T.bd}`,
              height: 34,
              padding: '0 14px',
            }}
            onClick={() => setFilter(id)}
          >
            {label}
          </button>
        ))}
      </div>
      <div className="ow-table">
        <div
          className="ow-table-head"
          style={{ gridTemplateColumns: '72px 88px 1.4fr 1.2fr 84px 92px 72px 84px' }}
        >
          {['TIME', 'STATION', 'PLAYERS', 'TITLE', 'LENGTH', 'AMOUNT', 'PAY', 'STATE'].map((c) => (
            <span key={c}>{c}</span>
          ))}
        </div>
        {rows.map((r, i) => {
          const payTone =
            r[6] === 'UPI'
              ? [T.accTint, T.accInk]
              : r[6] === 'CASH'
                ? [T.posTint, T.posInk3]
                : r[6] === 'CARD'
                  ? [T.chip, T.ink2b]
                  : [T.chip, T.faint];
          const stateTone =
            r[7] === 'live' ? [T.warnTint, T.warn] : r[7] === 'refund' ? [T.dangerTint, T.danger] : payTone;
          return (
            <div
              key={i}
              className="ow-table-row"
              style={{ gridTemplateColumns: '72px 88px 1.4fr 1.2fr 84px 92px 72px 84px', cursor: 'default' }}
            >
              <span className="ow-mono" style={{ fontSize: 12.5 }}>
                {r[0]}
              </span>
              <span className="ow-mono" style={{ fontSize: 12.5, fontWeight: 700 }}>
                {r[1]}
              </span>
              <span style={{ fontSize: 13, color: 'var(--ow-ink3)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {r[2]}
              </span>
              <span style={{ fontSize: 13 }}>{r[3]}</span>
              <span className="ow-mono" style={{ fontSize: 12.5, color: 'var(--ow-ink3)' }}>
                {r[4]}
              </span>
              <span className="ow-mono" style={{ fontSize: 13, fontWeight: 700, textAlign: 'right' }}>
                {inr(r[5])}
              </span>
              <span className="ow-chip" style={{ background: payTone[0], color: payTone[1], justifySelf: 'start' }}>
                {r[6]}
              </span>
              <span className="ow-chip" style={{ background: stateTone[0], color: stateTone[1], justifySelf: 'start', textTransform: 'uppercase' }}>
                {r[7]}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export const MembersPage: React.FC = () => {
  const { T, openMember, toast } = useOwnerNav();
  const { selectedArena, hasPermission } = useAuth();
  const [q, setQ] = useState('');
  const [filt, setFilt] = useState('all');
  const [rows, setRows] = useState<MemberSearchRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [topSpend, setTopSpend] = useState<MemberSearchRow[]>([]);

  useEffect(() => {
    if (!selectedArena?.id || !hasPermission('member.view')) return;
    let cancelled = false;
    void (async () => {
      try {
        const analytics = await fetchMemberAnalytics(selectedArena.id);
        if (!cancelled) setTopSpend((analytics.top_spend as MemberSearchRow[]) || []);
      } catch {
        /* analytics optional */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedArena?.id, hasPermission]);

  useEffect(() => {
    if (!selectedArena?.id || !hasPermission('member.view')) return;
    if (q.trim().length < 3) {
      setRows(filt === 'all' ? topSpend.slice(0, 20) : []);
      return;
    }
    let cancelled = false;
    const handle = window.setTimeout(() => {
      setLoading(true);
      void searchMembers(selectedArena.id, q.trim())
        .then((data) => {
          if (!cancelled) {
            setRows(data);
            setError(null);
          }
        })
        .catch((err) => {
          if (!cancelled) setError(readableMemberError(err, 'Search failed'));
        })
        .finally(() => {
          if (!cancelled) setLoading(false);
        });
    }, 280);
    return () => {
      cancelled = true;
      window.clearTimeout(handle);
    };
  }, [q, selectedArena?.id, hasPermission, topSpend, filt]);

  const visible = rows.filter((m) => {
    if (filt === 'blocked' && !m.blocked) return false;
    return true;
  });

  const onAdd = async () => {
    if (!selectedArena?.id || !hasPermission('member.create')) {
      toast('Permission required', 'member.create');
      return;
    }
    const fullName = window.prompt('Full name');
    if (!fullName?.trim()) return;
    const phone = window.prompt('Phone');
    if (!phone?.trim()) return;
    try {
      const created = await createMember({
        arenaId: selectedArena.id,
        memberId: crypto.randomUUID(),
        fullName: fullName.trim(),
        phone: phone.trim(),
        idempotencyKey: crypto.randomUUID(),
      });
      toast('Member created', created.full_name);
      openMember(created.id);
    } catch (err) {
      toast('Create failed', readableMemberError(err, 'Unable to create'));
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
        <input className="ow-field" style={{ width: 280 }} placeholder="Search phone or name (min 3)" value={q} onChange={(e) => setQ(e.target.value)} />
        {([['all', 'All'], ['blocked', 'Blocked']] as const).map(([id, label]) => (
          <button key={id} type="button" className="ow-btn" style={{ height: 34, padding: '0 14px', background: filt === id ? T.accTint : T.panel, color: filt === id ? T.accInk : T.ink2b, border: `1px solid ${filt === id ? T.accBd : T.bd}` }} onClick={() => setFilt(id)}>
            {label}
          </button>
        ))}
        <span style={{ flex: 1 }} />
        <button type="button" className="ow-btn ow-btn-accent" onClick={() => void onAdd()}>Add member</button>
      </div>
      {error && <div style={{ color: T.danger, fontSize: 13 }}>{error}</div>}
      {loading && <div style={{ fontSize: 13, color: 'var(--ow-muted)' }}>Searching…</div>}
      <div className="ow-table">
        <div className="ow-table-head" style={{ gridTemplateColumns: '1.5fr 130px 84px 104px 120px' }}>
          {['MEMBER', 'PHONE', 'VISITS', 'SPEND', 'LAST'].map((c, i) => (
            <span key={c} style={{ textAlign: i >= 2 ? 'right' : 'left' }}>{c}</span>
          ))}
        </div>
        {visible.map((m) => (
          <div key={m.id} className="ow-table-row" style={{ gridTemplateColumns: '1.5fr 130px 84px 104px 120px' }} onClick={() => openMember(m.id)}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 11, minWidth: 0 }}>
              <span className="ow-avatar" style={{ width: 30, height: 30, fontSize: 10.5, background: m.blocked ? T.dangerTint : T.accTint, color: m.blocked ? T.danger : T.accent }}>{initials(m.full_name)}</span>
              <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                <span style={{ fontSize: 13.5, fontWeight: 600, color: m.blocked ? T.danger : T.ink, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{m.full_name}</span>
                <span style={{ fontSize: 11.5, color: 'var(--ow-faint)' }}>{m.blocked ? 'Blocked' : m.member_code || 'Active'}</span>
              </div>
            </div>
            <span className="ow-mono" style={{ fontSize: 12.5, color: 'var(--ow-ink3)' }}>{m.phone_masked || m.phone}</span>
            <span className="ow-mono" style={{ fontSize: 13, textAlign: 'right' }}>{m.visit_count ?? '—'}</span>
            <span className="ow-mono" style={{ fontSize: 13, fontWeight: 700, textAlign: 'right' }}>{m.total_spend != null ? String(m.total_spend) : '—'}</span>
            <span style={{ fontSize: 12.5, color: 'var(--ow-faint)', textAlign: 'right' }}>{m.last_visit_at ? String(m.last_visit_at).slice(0, 10) : '—'}</span>
          </div>
        ))}
        {!loading && visible.length === 0 && (
          <div style={{ padding: 24, color: 'var(--ow-muted)', fontSize: 13 }}>
            {q.trim().length < 3 ? 'Type at least 3 characters to search, or browse top spenders.' : 'No members match.'}
          </div>
        )}
      </div>
    </div>
  );
};

export const MemberRecordPage: React.FC = () => {
  const { selectedMemberId, setScreen, toast, T } = useOwnerNav();
  const { selectedArena, hasPermission } = useAuth();
  const [m, setM] = useState<MemberRecord | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!selectedArena?.id || !selectedMemberId || !hasPermission('member.view')) return;
    let cancelled = false;
    setLoading(true);
    void getMember(selectedArena.id, selectedMemberId)
      .then((data) => { if (!cancelled) setM(data); })
      .catch((err) => { if (!cancelled) toast('Load failed', readableMemberError(err, 'Unable to load member')); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [selectedArena?.id, selectedMemberId, hasPermission, toast]);

  if (loading || !m) {
    return <div style={{ padding: 24, color: 'var(--ow-muted)' }}>{loading ? 'Loading…' : 'Member not found'}</div>;
  }

  const stats = m.stats || {};
  const loyalty = m.loyalty || {};
  const membership = m.membership;
  const sessions = m.recent_sessions || [];
  const tiles = [
    { label: 'Membership', value: membership?.plan_name || 'None', sub: membership?.ends_at ? `Ends ${String(membership.ends_at).slice(0, 10)}` : 'Walk-in pricing', fg: membership ? T.posInk3 : T.ink3 },
    { label: 'Lifetime', value: String(stats.visit_count ?? 0), sub: 'Visits recorded', fg: T.ink },
    { label: 'Lifetime spend', value: String(stats.total_spend ?? '0.00'), sub: 'Settled orders', fg: T.ink },
    { label: 'Wallet / loyalty', value: `${m.wallet_balance ?? '0.00'} / ${loyalty.points ?? 0}`, sub: (loyalty.tier as { label?: string } | null | undefined)?.label || 'Tier', fg: T.warn },
  ];

  const onBlock = async () => {
    if (!selectedArena?.id || !hasPermission('member.block')) { toast('Permission required', 'member.block'); return; }
    const next = !m.blocked;
    let reason: string | undefined;
    if (next) { reason = window.prompt('Block reason') || undefined; if (!reason?.trim()) return; }
    try {
      const updated = await setMemberBlocked({ arenaId: selectedArena.id, memberId: m.id, blocked: next, reason });
      setM((prev) => (prev ? { ...prev, ...updated } : updated));
      toast(next ? 'Blocked' : 'Unblocked', m.full_name);
    } catch (err) {
      toast('Failed', readableMemberError(err, 'Unable to update block'));
    }
  };

  const onTopup = async () => {
    if (!selectedArena?.id || !hasPermission('member.wallet')) { toast('Permission required', 'member.wallet'); return; }
    const amount = window.prompt('Top-up amount');
    if (!amount?.trim()) return;
    try {
      await walletTopup({ arenaId: selectedArena.id, memberId: m.id, amount: amount.trim() });
      setM(await getMember(selectedArena.id, m.id));
      toast('Wallet topped up', amount);
    } catch (err) {
      toast('Top-up failed', readableMemberError(err, 'Unable to top up'));
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <button type="button" className="ow-link" onClick={() => setScreen('members')} style={{ width: 'fit-content' }}>← All members</button>
      <div className="ow-panel" style={{ padding: '20px 22px', display: 'flex', alignItems: 'center', gap: 16 }}>
        <span className="ow-avatar" style={{ width: 54, height: 54, fontSize: 16 }}>{initials(m.full_name)}</span>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
          <span style={{ fontWeight: 700, fontSize: 21, letterSpacing: '-0.015em' }}>{m.full_name}</span>
          <span className="ow-mono" style={{ fontSize: 12.5, color: 'var(--ow-muted)' }}>{m.phone} · {m.member_code || '—'}</span>
        </div>
        <span style={{ flex: 1 }} />
        <button type="button" className="ow-btn ow-btn-accent" onClick={() => void onTopup()}>Wallet top-up</button>
        <button type="button" className="ow-btn ow-btn-danger" onClick={() => void onBlock()}>{m.blocked ? 'Unblock' : 'Block'}</button>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 14 }}>
        {tiles.map((t) => (
          <div key={t.label} className="ow-kpi" style={{ gap: 5, padding: '15px 18px' }}>
            <span className="ow-kpi-label">{t.label}</span>
            <span className="ow-kpi-value" style={{ fontSize: 23, color: t.fg }}>{t.value}</span>
            <span className="ow-kpi-sub">{t.sub}</span>
          </div>
        ))}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 340px', gap: 14, alignItems: 'start' }}>
        <div className="ow-panel">
          <span style={{ fontWeight: 700, fontSize: 15 }}>Recent visits</span>
          {sessions.map((v) => (
            <div key={String(v.id)} style={{ display: 'grid', gridTemplateColumns: '110px 90px 1fr 90px', gap: 12, padding: '12px 0', borderTop: '1px solid var(--ow-hair)', marginTop: 8, alignItems: 'center' }}>
              <span className="ow-mono" style={{ fontSize: 12.5, color: 'var(--ow-ink3)' }}>{String(v.started_at || '').slice(0, 10)}</span>
              <span className="ow-mono" style={{ fontSize: 12.5, fontWeight: 700 }}>{String(v.station_name || '—')}</span>
              <span style={{ fontSize: 13, color: 'var(--ow-ink3)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{String(v.game_title || '')}</span>
              <span className="ow-mono" style={{ fontSize: 12.5, textAlign: 'right', color: 'var(--ow-ink3)' }}>{String(v.status || '')}</span>
            </div>
          ))}
          {sessions.length === 0 && <p style={{ marginTop: 12, fontSize: 13, color: 'var(--ow-muted)' }}>No recent sessions.</p>}
        </div>
        <div className="ow-panel">
          <span style={{ fontWeight: 700, fontSize: 15 }}>Profile</span>
          {[['Outstanding', m.outstanding_balance || '0.00'], ['Notes', m.notes || '—'], ['Tags', (m.tags || []).map((t) => t.label).join(', ') || '—'], ['Blocked', m.blocked ? m.blocked_reason || 'Yes' : 'No']].map(([k, v]) => (
            <div key={String(k)} style={{ display: 'flex', alignItems: 'baseline', gap: 10, padding: '11px 0', borderTop: '1px solid var(--ow-hair)', marginTop: 8 }}>
              <span style={{ fontSize: 13, color: 'var(--ow-muted)', flex: 1 }}>{k}</span>
              <span className="ow-mono" style={{ fontSize: 12.5, fontWeight: 600 }}>{v}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export const MembershipsPage: React.FC = () => {
  const { T, openMember, toast } = useOwnerNav();
  const { selectedArena, hasPermission } = useAuth();
  const [plans, setPlans] = useState<Array<Record<string, unknown>>>([]);
  const [lapse, setLapse] = useState<MemberSearchRow[]>([]);

  useEffect(() => {
    if (!selectedArena?.id) return;
    let cancelled = false;
    void (async () => {
      try {
        if (hasPermission('membership.manage')) {
          const list = await listMembershipPlans(selectedArena.id);
          if (!cancelled) setPlans(list as Array<Record<string, unknown>>);
        }
        if (hasPermission('member.view')) {
          const analytics = await fetchMemberAnalytics(selectedArena.id);
          if (!cancelled) setLapse((analytics.no_visit_90d as MemberSearchRow[]) || []);
        }
      } catch (err) {
        if (!cancelled) toast('Memberships', readableMemberError(err, 'Unable to load'));
      }
    })();
    return () => { cancelled = true; };
  }, [selectedArena?.id, hasPermission, toast]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
        {plans.length === 0 && (
          <div className="ow-panel" style={{ padding: '19px 21px', gridColumn: '1 / -1' }}>
            <span style={{ fontSize: 13, color: 'var(--ow-muted)' }}>No membership plans yet. Create via membership_plan_upsert.</span>
          </div>
        )}
        {plans.map((p) => (
          <div key={String(p.id)} className="ow-panel" style={{ padding: '19px 21px', borderColor: p.active ? T.accBd : T.bd, display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 9 }}>
              <span style={{ fontWeight: 700, fontSize: 16 }}>{String(p.name)}</span>
              <span style={{ flex: 1 }} />
              <span className="ow-chip" style={{ background: p.active ? T.posTint : T.chip, color: p.active ? T.posInk3 : T.ink3 }}>{p.active ? 'ACTIVE' : 'PAUSED'}</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
              <span className="ow-mono" style={{ fontWeight: 700, fontSize: 28, letterSpacing: '-0.02em' }}>{inr(Number(p.price) || 0)}</span>
              <span style={{ fontSize: 12.5, color: 'var(--ow-faint)' }}>/ {String(p.period_days)}d</span>
            </div>
          </div>
        ))}
      </div>
      <div className="ow-panel">
        <span style={{ fontWeight: 700, fontSize: 15 }}>No visit in 90 days</span>
        {lapse.map((e) => (
          <div key={e.id} role="button" tabIndex={0} onClick={() => openMember(e.id)} onKeyDown={(ev) => ev.key === 'Enter' && openMember(e.id)} style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 11, padding: '11px 0', borderTop: '1px solid var(--ow-hair)', marginTop: 8 }}>
            <span className="ow-avatar" style={{ width: 30, height: 30, fontSize: 10.5 }}>{initials(e.full_name)}</span>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13.5, fontWeight: 600 }}>{e.full_name}</div>
              <div className="ow-mono" style={{ fontSize: 11, color: 'var(--ow-faint)' }}>{e.phone_masked || e.phone}</div>
            </div>
            <span className="ow-chip" style={{ background: T.warnTint, color: T.warn }}>{e.last_visit_at ? String(e.last_visit_at).slice(0, 10) : 'Never'}</span>
          </div>
        ))}
        {lapse.length === 0 && <p style={{ marginTop: 12, fontSize: 13, color: 'var(--ow-muted)' }}>No lapse cohort right now.</p>}
      </div>
    </div>
  );
};

export const GamesPage: React.FC = () => {
  const { T, toast } = useOwnerNav();
  const [tab, setTab] = useState<'library' | 'requests'>('library');

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div className="ow-tabs">
        <button type="button" className={`ow-tab${tab === 'library' ? ' is-active' : ''}`} onClick={() => setTab('library')}>
          Library
        </button>
        <button type="button" className={`ow-tab${tab === 'requests' ? ' is-active' : ''}`} onClick={() => setTab('requests')}>
          Requests
        </button>
        <span style={{ flex: 1 }} />
        <button type="button" className="ow-btn ow-btn-accent" onClick={() => toast('Add game', 'Catalogue RPC pending')}>
          Add title
        </button>
      </div>
      {tab === 'library' ? (
        <div className="ow-table">
          <div className="ow-table-head" style={{ gridTemplateColumns: '1.6fr 120px 80px 1fr 80px' }}>
            {['TITLE', 'PLATFORM', 'RATING', 'INSTALLED ON', 'HOURS'].map((c) => (
              <span key={c}>{c}</span>
            ))}
          </div>
          {FIXTURE_GAMES.map((g) => (
            <div key={g.t} className="ow-table-row" style={{ gridTemplateColumns: '1.6fr 120px 80px 1fr 80px', cursor: 'default' }}>
              <span style={{ fontSize: 13.5, fontWeight: 600 }}>{g.t}</span>
              <span className="ow-mono" style={{ fontSize: 12.5, color: 'var(--ow-ink3)' }}>
                {g.plat}
              </span>
              <span
                className="ow-chip"
                style={{
                  background: g.r === '18+' ? T.dangerTint : g.r === '12+' || g.r === '16+' ? T.warnTint : T.posTint,
                  color: g.r === '18+' ? T.danger : g.r === '12+' || g.r === '16+' ? T.warn : T.posInk3,
                  justifySelf: 'start',
                }}
              >
                {g.r}
              </span>
              <span style={{ fontSize: 12.5, color: 'var(--ow-ink3)' }}>{g.on.join(' · ')}</span>
              <span className="ow-mono" style={{ fontSize: 13, fontWeight: 700, textAlign: 'right' }}>
                {g.hrs} h
              </span>
            </div>
          ))}
        </div>
      ) : (
        <div className="ow-panel">
          <span style={{ fontWeight: 700, fontSize: 15 }}>Counter requests</span>
          <p style={{ marginTop: 10, fontSize: 13, color: 'var(--ow-muted)' }}>
            Staff-flagged titles from idle stations. Buy / hold decisions stay with the owner.
          </p>
        </div>
      )}
    </div>
  );
};

export const InventoryPage: React.FC = () => {
  const { T, toast } = useOwnerNav();
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ display: 'flex', gap: 8 }}>
        <button type="button" className="ow-btn ow-btn-accent" onClick={() => toast('Receive stock')}>
          Receive
        </button>
        <button type="button" className="ow-btn ow-btn-ghost" onClick={() => toast('Adjust count')}>
          Adjust
        </button>
        <button type="button" className="ow-btn ow-btn-ghost" onClick={() => toast('Restocked everything low', 'Counter tablet updated')}>
          Restock all low
        </button>
      </div>
      <div className="ow-table">
        <div className="ow-table-head" style={{ gridTemplateColumns: '1.5fr 100px 100px 1fr 120px' }}>
          {['PRODUCT', 'STOCK', 'PAR', 'SOLD', ''].map((c) => (
            <span key={c || 'a'}>{c}</span>
          ))}
        </div>
        {FIXTURE_PRODUCTS.map((p) => (
          <div key={p.name} className="ow-table-row" style={{ gridTemplateColumns: '1.5fr 100px 100px 1fr 120px', cursor: 'default' }}>
            <span style={{ fontSize: 13.5, fontWeight: 600 }}>{p.name}</span>
            <span className="ow-mono" style={{ fontSize: 13, fontWeight: 700, color: p.low ? T.danger : T.ink }}>
              {p.stock}
            </span>
            <span className="ow-mono" style={{ fontSize: 13, color: 'var(--ow-ink3)' }}>
              {p.par}
            </span>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ flex: 1, height: 7, borderRadius: 4, background: 'var(--ow-chip)' }}>
                <div
                  style={{
                    width: `${Math.min(100, (p.stock / p.par) * 100)}%`,
                    height: '100%',
                    borderRadius: 4,
                    background: p.low ? T.danger : T.pos,
                  }}
                />
              </div>
              <span style={{ fontSize: 12, color: 'var(--ow-faint)' }}>{p.sold}</span>
            </div>
            <button type="button" className="ow-btn ow-btn-ghost" style={{ height: 30, padding: '0 11px', fontSize: 12 }} onClick={() => toast('Restock', p.name)}>
              Restock
            </button>
          </div>
        ))}
      </div>
    </div>
  );
};

export const ExpensesPage: React.FC = () => {
  const { T, toast } = useOwnerNav();
  const total = FIXTURE_EXPENSES.reduce((s, e) => s + e.amt, 0);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
        <div className="ow-kpi">
          <span className="ow-kpi-label">This month</span>
          <span className="ow-kpi-value">{inr(total)}</span>
          <span className="ow-kpi-sub">Cash leaving the drawer</span>
        </div>
        <div className="ow-kpi">
          <span className="ow-kpi-label">Rough profit</span>
          <span className="ow-kpi-value" style={{ color: T.posInk3 }}>
            {inr(98000 - total)}
          </span>
          <span className="ow-kpi-sub">Before tax and depreciation</span>
        </div>
        <div className="ow-kpi">
          <span className="ow-kpi-label">Missing bills</span>
          <span className="ow-kpi-value" style={{ color: T.warn }}>
            1
          </span>
          <span className="ow-kpi-sub">Chase these before month end</span>
        </div>
      </div>
      <button type="button" className="ow-btn ow-btn-accent" style={{ width: 'fit-content' }} onClick={() => toast('Add expense')}>
        Add expense
      </button>
      <div className="ow-table">
        <div className="ow-table-head" style={{ gridTemplateColumns: '90px 120px 1.5fr 100px 80px 80px' }}>
          {['DATE', 'CATEGORY', 'NOTE', 'AMOUNT', 'MODE', 'BILL'].map((c) => (
            <span key={c}>{c}</span>
          ))}
        </div>
        {FIXTURE_EXPENSES.map((e) => (
          <div key={e.date + e.note} className="ow-table-row" style={{ gridTemplateColumns: '90px 120px 1.5fr 100px 80px 80px', cursor: 'default' }}>
            <span className="ow-mono" style={{ fontSize: 12.5 }}>
              {e.date}
            </span>
            <span style={{ fontSize: 13 }}>{e.cat}</span>
            <span style={{ fontSize: 13, color: 'var(--ow-ink3)' }}>{e.note}</span>
            <span className="ow-mono" style={{ fontSize: 13, fontWeight: 700 }}>
              {inr(e.amt)}
            </span>
            <span className="ow-mono" style={{ fontSize: 11 }}>
              {e.mode}
            </span>
            <span className="ow-chip" style={{ background: e.bill ? T.posTint : T.warnTint, color: e.bill ? T.posInk3 : T.warn, justifySelf: 'start' }}>
              {e.bill ? 'YES' : 'NO'}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
};

export const StaffPage: React.FC = () => {
  const { T, toast } = useOwnerNav();
  const perms = ['Floor', 'Members', 'Stock', 'Shift close', 'Reports', 'Settings', 'Refunds'];
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 400px', gap: 14, alignItems: 'start' }}>
      <div className="ow-table">
        <div className="ow-table-head" style={{ gridTemplateColumns: '1.4fr 120px 80px 100px' }}>
          {['NAME', 'ROLE', 'PIN', 'STATUS'].map((c) => (
            <span key={c}>{c}</span>
          ))}
        </div>
        {FIXTURE_STAFF.map((x) => (
          <div key={x.name} className="ow-table-row" style={{ gridTemplateColumns: '1.4fr 120px 80px 100px', cursor: 'default' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span
                className="ow-avatar"
                style={{
                  width: 30,
                  height: 30,
                  fontSize: 10.5,
                  background: x.role === 'OWNER' ? T.warnTint : T.accTint,
                  color: x.role === 'OWNER' ? T.warn : T.accent,
                }}
              >
                {initials(x.name)}
              </span>
              <span style={{ fontSize: 13.5, fontWeight: 600 }}>{x.name}</span>
            </div>
            <span className="ow-chip" style={{ background: x.role === 'OWNER' ? T.warnTint : T.chip, color: x.role === 'OWNER' ? T.warn : T.ink2b, justifySelf: 'start' }}>
              {x.role}
            </span>
            <span className="ow-mono" style={{ fontSize: 12.5 }}>
              {x.pin}
            </span>
            <span className="ow-chip" style={{ background: x.active ? T.posTint : T.panel, color: x.active ? T.posInk3 : T.muted, border: x.active ? 'none' : `1px solid ${T.bd}`, justifySelf: 'start' }}>
              {x.active ? 'ACTIVE' : 'OFF'}
            </span>
          </div>
        ))}
      </div>
      <div className="ow-panel">
        <span style={{ fontWeight: 700, fontSize: 15 }}>Role permissions</span>
        <span style={{ display: 'block', fontSize: 12.5, color: 'var(--ow-muted)', marginTop: 6, marginBottom: 10 }}>
          Tap to assign. Anything unassigned stays locked on that person’s tablet.
        </span>
        {perms.map((p) => (
          <button
            key={p}
            type="button"
            onClick={() => toast(p, 'Permission toggle (UI)')}
            style={{
              all: 'unset',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '11px 0',
              borderTop: '1px solid var(--ow-hair)',
              width: '100%',
            }}
          >
            <span style={{ fontSize: 13.5, fontWeight: 600 }}>{p}</span>
            <span className="ow-chip" style={{ background: T.posTint, color: T.posInk3 }}>
              ON
            </span>
          </button>
        ))}
      </div>
    </div>
  );
};

export const IntegrationsPage: React.FC = () => {
  const { T, toast } = useOwnerNav();
  const [on, setOn] = useState<Record<string, boolean>>(() =>
    Object.fromEntries(FIXTURE_INTEGRATIONS.map((x) => [x[0], x[4]])),
  );
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      {FIXTURE_INTEGRATIONS.map((x) => {
        const active = on[x[0]];
        return (
          <div key={x[0]} className="ow-panel" style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
                <span style={{ fontWeight: 700, fontSize: 15 }}>{x[1]}</span>
                <span className="ow-chip" style={{ background: active ? T.posTint : T.chip, color: active ? T.posInk3 : T.faint }}>
                  {active ? 'CONNECTED' : 'OFF'}
                </span>
              </div>
              <div style={{ fontSize: 13, color: 'var(--ow-muted)', marginTop: 4 }}>{x[2]}</div>
              <div className="ow-mono" style={{ fontSize: 11, color: 'var(--ow-faint)', marginTop: 4 }}>
                {x[3]}
              </div>
            </div>
            <button
              type="button"
              className="ow-btn ow-btn-ghost"
              onClick={() => {
                setOn((s) => ({ ...s, [x[0]]: !active }));
                toast(x[1] + (active ? ' disconnected' : ' connected'));
              }}
            >
              {active ? 'Disconnect' : 'Connect'}
            </button>
          </div>
        );
      })}
    </div>
  );
};

export const SettingsPage: React.FC = () => {
  const { toast } = useOwnerNav();
  const [tab, setTab] = useState('arena');
  const tabs = [
    ['arena', 'Arena'],
    ['hours', 'Hours'],
    ['receipts', 'Receipts'],
    ['tax', 'Tax'],
    ['devices', 'Devices'],
    ['notify', 'Notifications'],
    ['checklist', 'Close checklist'],
  ] as const;

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '230px 1fr', gap: 16, alignItems: 'start' }}>
      <div className="ow-panel" style={{ padding: 10, display: 'flex', flexDirection: 'column', gap: 2 }}>
        {tabs.map(([id, label]) => (
          <button
            key={id}
            type="button"
            className="ow-nav-item"
            style={{ background: tab === id ? 'var(--ow-accTint)' : 'transparent' }}
            onClick={() => setTab(id)}
          >
            <span className="ow-nav-dot" style={{ background: tab === id ? 'var(--ow-accent)' : 'var(--ow-fainter)' }} />
            <span className="ow-nav-text" style={{ fontWeight: tab === id ? 700 : 500 }}>
              {label}
            </span>
          </button>
        ))}
      </div>
      <div className="ow-panel" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <span style={{ fontWeight: 700, fontSize: 15 }}>{tabs.find((t) => t[0] === tab)?.[1]}</span>
        {(
          tab === 'arena'
            ? [
                ['Display name', '404 Arena'],
                ['City', 'Thrissur'],
                ['Currency', 'INR'],
                ['Timezone', 'Asia/Kolkata'],
              ]
            : tab === 'devices'
              ? [
                  ['Counter tablet', 'Lenovo Tab · Android 14'],
                  ['Status', 'Online · synced 12s ago'],
                ]
              : [
                  ['Setting', 'Matches prototype W11'],
                  ['Note', 'Bound to arena_settings after settings RPCs'],
                ]
        ).map(([k, v]) => (
          <div key={k} style={{ display: 'flex', alignItems: 'baseline', gap: 12, padding: '10px 0', borderTop: '1px solid var(--ow-hair)' }}>
            <span style={{ fontSize: 13, color: 'var(--ow-muted)', width: 140 }}>{k}</span>
            <span className="ow-mono" style={{ fontSize: 13, fontWeight: 600 }}>
              {v}
            </span>
          </div>
        ))}
        <button type="button" className="ow-btn ow-btn-accent" style={{ width: 'fit-content' }} onClick={() => toast('Settings saved')}>
          Save
        </button>
      </div>
    </div>
  );
};

export const StationsAdminPage: React.FC = () => {
  const { T, toast } = useOwnerNav();
  const stations = [
    { name: 'PS-01', zone: 'PS ZONE', type: 'PS5', rate: 120, status: 'live', seats: 2 },
    { name: 'PS-02', zone: 'PS ZONE', type: 'PS5', rate: 120, status: 'live', seats: 2 },
    { name: 'PS-03', zone: 'PS ZONE', type: 'PS4 Pro', rate: 100, status: 'idle', seats: 4 },
    { name: 'VR-01', zone: 'VR', type: 'VR', rate: 200, status: 'maint', seats: 1 },
    { name: 'POOL-01', zone: 'POOL', type: 'Pool', rate: 80, status: 'over', seats: 4 },
  ];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <button type="button" className="ow-btn ow-btn-accent" style={{ width: 'fit-content' }} onClick={() => toast('Add station')}>
        Add station
      </button>
      <div className="ow-table">
        <div className="ow-table-head" style={{ gridTemplateColumns: '100px 120px 120px 80px 80px 100px' }}>
          {['STATION', 'ZONE', 'TYPE', 'RATE', 'SEATS', 'STATUS'].map((c) => (
            <span key={c}>{c}</span>
          ))}
        </div>
        {stations.map((s) => {
          const stFg = s.status === 'live' ? T.posInk3 : s.status === 'maint' ? T.danger : s.status === 'over' ? T.danger : T.ink3;
          return (
            <div key={s.name} className="ow-table-row" style={{ gridTemplateColumns: '100px 120px 120px 80px 80px 100px', cursor: 'default' }}>
              <span className="ow-mono" style={{ fontWeight: 700, fontSize: 12.5 }}>
                {s.name}
              </span>
              <span style={{ fontSize: 13 }}>{s.zone}</span>
              <span style={{ fontSize: 13 }}>{s.type}</span>
              <span className="ow-mono" style={{ fontSize: 13 }}>
                {inr(s.rate)}
              </span>
              <span className="ow-mono" style={{ fontSize: 13 }}>
                {s.seats}
              </span>
              <span className="ow-mono" style={{ fontSize: 11, fontWeight: 700, color: stFg, textTransform: 'uppercase' }}>
                {s.status}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
};
