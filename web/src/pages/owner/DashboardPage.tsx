import React, { useEffect, useMemo, useState } from 'react';
import { useAuth } from '../../context/AuthContext';
import { fetchFloorSnapshot, type FloorSnapshotResponse } from '../../services/floor';
import {
  dashboardKpis,
  expiringMembers,
  hourlyBars,
  initials,
  lowStockProducts,
} from '../../data/ownerFixtures';
import { useOwnerNav } from '../../components/owner/OwnerShell';

function stationPresentation(
  st: FloorSnapshotResponse['stations'][0],
  live: FloorSnapshotResponse['live_sessions'],
  T: ReturnType<typeof useOwnerNav>['T'],
) {
  if (st.status === 'maintenance') {
    return { who: st.status_reason || 'Maintenance', state: 'MAINT', bg: T.dangerTint, fg: T.danger };
  }
  if (st.status !== 'active') {
    return { who: 'Offline', state: 'OFF', bg: T.chip, fg: T.muted };
  }
  const sess = live.find((s) => s.station_id === st.id && (s.status === 'active' || s.status === 'paused'));
  if (!sess) {
    return { who: 'Free', state: 'IDLE', bg: T.chip, fg: T.muted };
  }
  const who = sess.member_name || sess.game_title || `${sess.player_count} players`;
  if (sess.planned_end_at) {
    const rem = (new Date(sess.planned_end_at).getTime() - Date.now()) / 60000;
    if (rem < 0) return { who, state: 'OVER', bg: T.dangerTint, fg: T.danger };
    if (rem <= 5) return { who, state: 'LAST 5', bg: T.warnTint, fg: T.warn };
  }
  return { who, state: 'LIVE', bg: T.posTint, fg: T.posInk3 };
}

export const DashboardPage: React.FC = () => {
  const { selectedArena, user } = useAuth();
  const { T, range, setScreen, openMember, toast } = useOwnerNav();
  const [floor, setFloor] = useState<FloorSnapshotResponse | null>(null);

  useEffect(() => {
    if (!selectedArena?.id) return;
    let cancelled = false;
    const load = async () => {
      try {
        const snap = await fetchFloorSnapshot(selectedArena.id);
        if (!cancelled) setFloor(snap);
      } catch {
        if (!cancelled) setFloor(null);
      }
    };
    void load();
    const id = window.setInterval(load, 10000);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, [selectedArena?.id]);

  const kpis = useMemo(
    () => dashboardKpis(range, T, user?.display_name || 'Staff'),
    [range, T, user?.display_name],
  );
  const bars = useMemo(() => hourlyBars(T), [T]);
  const expiring = expiringMembers();
  const low = lowStockProducts();

  const floorRows = useMemo(() => {
    if (!floor) {
      return [
        { name: 'PS-01', who: 'Arjun K', state: 'LIVE', bg: T.posTint, fg: T.posInk3 },
        { name: 'PS-02', who: 'Sreya P · Kiran', state: 'LAST 5', bg: T.warnTint, fg: T.warn },
        { name: 'PS-03', who: 'Free', state: 'IDLE', bg: T.chip, fg: T.muted },
        { name: 'PS-04', who: 'Devika S', state: 'LIVE', bg: T.posTint, fg: T.posInk3 },
        { name: 'VR-01', who: 'Controller fault', state: 'MAINT', bg: T.dangerTint, fg: T.danger },
        { name: 'POOL-01', who: 'Walk-in ×2', state: 'OVER', bg: T.dangerTint, fg: T.danger },
      ];
    }
    return floor.stations.slice(0, 8).map((st) => {
      const p = stationPresentation(st, floor.live_sessions, T);
      return { name: st.name, ...p };
    });
  }, [floor, T]);

  const busy = floorRows.filter((r) => r.state === 'LIVE' || r.state === 'LAST 5' || r.state === 'OVER').length;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 14 }}>
        {kpis.map((k) => (
          <div key={k.label} className="ow-kpi">
            <span className="ow-kpi-label">{k.label}</span>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 9 }}>
              <span className="ow-kpi-value">{k.value}</span>
              <span className="ow-kpi-delta" style={{ background: k.deltaBg, color: k.deltaFg }}>
                {k.delta}
              </span>
            </div>
            <span className="ow-kpi-sub">{k.sub}</span>
          </div>
        ))}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 372px', gap: 14, alignItems: 'start' }}>
        <div className="ow-panel" style={{ padding: '18px 20px 14px' }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 16 }}>
            <span style={{ fontWeight: 700, fontSize: 15 }}>Revenue by hour</span>
            <span style={{ fontSize: 12, color: 'var(--ow-faint)' }}>Peak 20:00</span>
            <span style={{ flex: 1 }} />
            <span className="ow-mono" style={{ fontSize: 11, color: 'var(--ow-accent)' }}>
              SESSIONS ■ SNACKS ■
            </span>
          </div>
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 9, height: 168 }}>
            {bars.map((h) => (
              <div
                key={h.hour}
                style={{
                  flex: 1,
                  display: 'flex',
                  flexDirection: 'column',
                  justifyContent: 'flex-end',
                  alignItems: 'center',
                  gap: 6,
                  height: '100%',
                }}
              >
                <span className="ow-mono" style={{ fontSize: 9.5, color: 'var(--ow-faint)' }}>
                  {h.amt}
                </span>
                <div
                  style={{
                    width: '100%',
                    display: 'flex',
                    flexDirection: 'column',
                    justifyContent: 'flex-end',
                    gap: 2,
                    height: h.h,
                  }}
                >
                  <div style={{ height: h.snackH, borderRadius: '4px 4px 0 0', background: 'var(--ow-chart3)' }} />
                  <div style={{ flex: 1, borderRadius: h.rad, background: h.fill }} />
                </div>
                <span className="ow-mono" style={{ fontSize: 9.5, color: 'var(--ow-muted)' }}>
                  {h.hour}
                </span>
              </div>
            ))}
          </div>
        </div>

        <div className="ow-panel">
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 9, marginBottom: 6 }}>
            <span style={{ fontWeight: 700, fontSize: 15 }}>Floor right now</span>
            <span style={{ flex: 1 }} />
            <span className="ow-mono" style={{ fontSize: 11, color: 'var(--ow-muted)' }}>
              {busy} BUSY
            </span>
          </div>
          {floorRows.map((f) => (
            <div
              key={f.name}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 11,
                padding: '11px 0',
                borderTop: '1px solid var(--ow-hair)',
              }}
            >
              <span className="ow-mono" style={{ fontWeight: 700, fontSize: 12.5, width: 62, flex: 'none' }}>
                {f.name}
              </span>
              <span
                style={{
                  fontSize: 12.5,
                  color: 'var(--ow-ink3)',
                  flex: 1,
                  minWidth: 0,
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
              >
                {f.who}
              </span>
              <span className="ow-chip" style={{ background: f.bg, color: f.fg }}>
                {f.state}
              </span>
            </div>
          ))}
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, alignItems: 'start' }}>
        <div className="ow-panel">
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 9, marginBottom: 4 }}>
            <span style={{ fontWeight: 700, fontSize: 15 }}>Memberships lapsing</span>
            <span style={{ flex: 1 }} />
            <button type="button" className="ow-link" onClick={() => setScreen('plans')}>
              All memberships
            </button>
          </div>
          {expiring.length === 0 ? (
            <div className="ow-empty">Nobody lapses in the next seven days. The next renewal is due in 12 days.</div>
          ) : (
            expiring.map((e) => (
              <div
                key={e.id}
                role="button"
                tabIndex={0}
                onClick={() => openMember(e.id)}
                onKeyDown={(ev) => ev.key === 'Enter' && openMember(e.id)}
                style={{
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 11,
                  padding: '11px 0',
                  borderTop: '1px solid var(--ow-hair)',
                }}
              >
                <span
                  className="ow-avatar"
                  style={{ width: 30, height: 30, fontSize: 10.5 }}
                >
                  {initials(e.name)}
                </span>
                <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minWidth: 0 }}>
                  <span style={{ fontSize: 13.5, fontWeight: 600 }}>{e.name}</span>
                  <span className="ow-mono" style={{ fontSize: 11, color: 'var(--ow-faint)' }}>
                    {e.phone}
                  </span>
                </div>
                <span className="ow-chip" style={{ background: 'var(--ow-warnTint)', color: 'var(--ow-warn)' }}>
                  {e.expDays}d
                </span>
              </div>
            ))
          )}
        </div>

        <div className="ow-panel">
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 9, marginBottom: 4 }}>
            <span style={{ fontWeight: 700, fontSize: 15 }}>Reorder before the weekend</span>
            <span style={{ flex: 1 }} />
            <button type="button" className="ow-link" onClick={() => setScreen('products')}>
              Inventory
            </button>
          </div>
          {low.length === 0 ? (
            <div className="ow-empty">Every product is above its par level. Nothing to order before Saturday.</div>
          ) : (
            low.map((p) => (
              <div
                key={p.name}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 11,
                  padding: '11px 0',
                  borderTop: '1px solid var(--ow-hair)',
                }}
              >
                <span style={{ fontSize: 13.5, fontWeight: 600, flex: 1, minWidth: 0 }}>{p.name}</span>
                <span style={{ fontSize: 12, color: 'var(--ow-faint)' }}>{p.sold}</span>
                <span
                  className="ow-mono"
                  style={{ fontWeight: 700, fontSize: 13, width: 38, textAlign: 'right', color: 'var(--ow-danger)' }}
                >
                  {p.stock}
                </span>
                <button
                  type="button"
                  className="ow-btn ow-btn-ghost"
                  style={{ height: 30, padding: '0 11px', fontSize: 12 }}
                  onClick={() => toast('Restock queued', p.name)}
                >
                  Restock
                </button>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
};
