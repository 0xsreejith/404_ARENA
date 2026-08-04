import React, { useEffect, useState } from 'react';
import { useAuth } from '../context/AuthContext';
import {
  fetchFloorSnapshot,
  startSessionRPC,
  pauseSessionRPC,
  resumeSessionRPC,
  stopSessionRPC,
  FloorSnapshotResponse,
  Station,
  LiveSession,
} from '../services/floor';
import { CheckoutPanel } from './CheckoutPanel';
import { Play, Pause, Square, RefreshCw, ShoppingCart } from 'lucide-react';

type CheckoutTarget = {
  orderId: string;
  sessionId: string;
  memberName?: string;
};

export const LiveFloorGrid: React.FC = () => {
  const { selectedArena, hasPermission } = useAuth();
  const [snapshot, setSnapshot] = useState<FloorSnapshotResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [selectedZoneId, setSelectedZoneId] = useState<string | null>(null);
  const [now, setNow] = useState<Date>(new Date());
  const [actionError, setActionError] = useState<string | null>(null);
  const [checkout, setCheckout] = useState<CheckoutTarget | null>(null);
  const [showUnbilled, setShowUnbilled] = useState(false);

  // Start Session Modal State
  const [startModalStation, setStartModalStation] = useState<Station | null>(null);
  const [selectedPlanId, setSelectedPlanId] = useState<string>('');
  const [playerCount, setPlayerCount] = useState<number>(1);
  const [submitting, setSubmitting] = useState(false);

  const loadFloorData = async () => {
    if (!selectedArena) return;
    try {
      const data = await fetchFloorSnapshot(selectedArena.id);
      setSnapshot(data);
      setActionError(null);
    } catch (err: unknown) {
      const message =
        err && typeof err === 'object' && 'message' in err
          ? String((err as { message: unknown }).message)
          : 'Failed to load floor';
      setActionError(message);
    } finally {
      setLoading(false);
    }
  };

  // 10s floor snapshot refresh + 1s timer tick
  useEffect(() => {
    loadFloorData();
    const fetchInterval = setInterval(loadFloorData, 10000);
    const tickInterval = setInterval(() => setNow(new Date()), 1000);

    return () => {
      clearInterval(fetchInterval);
      clearInterval(tickInterval);
    };
  }, [selectedArena?.id]);

  if (loading || !snapshot) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '300px', color: 'var(--accent)', fontFamily: 'var(--font-mono)' }}>
        LOADING LIVE FLOOR TELEMETRY...
      </div>
    );
  }

  const primaryColor = selectedArena?.branding.primary_color || '#7CFF4F';
  const showZoneFilters = snapshot.zones.length > 1;
  const filteredStations =
    showZoneFilters && selectedZoneId
      ? snapshot.stations.filter((s) => s.zone_id === selectedZoneId)
      : snapshot.stations;

  const deriveStationState = (station: Station, session?: LiveSession) => {
    if (station.status === 'maintenance') return 'MAINTENANCE';
    if (station.status === 'inactive') return 'INACTIVE';
    if (!session) return 'IDLE';
    if (session.status === 'paused') return 'PAUSED';
    if (!session.planned_end_at) return 'LIVE';

    const plannedEnd = new Date(session.planned_end_at);
    const diffSec = Math.floor((plannedEnd.getTime() - now.getTime()) / 1000);
    if (diffSec <= 0) return 'OVERTIME';
    if (diffSec <= 600) return 'ENDING';
    return 'LIVE';
  };

  const calculateFormattedTimer = (session?: LiveSession) => {
    if (!session) return '00:00:00';
    if (session.status === 'paused') return 'PAUSED';

    const startedAt = new Date(session.started_at);
    const totalPaused = session.total_paused_seconds || 0;

    if (session.planned_end_at) {
      const plannedEnd = new Date(session.planned_end_at);
      const diffSec = Math.floor((plannedEnd.getTime() - now.getTime()) / 1000);

      if (diffSec < 0) {
        const overtimeSec = Math.abs(diffSec);
        return `+${formatHHMMSS(overtimeSec)}`;
      }
      return formatHHMMSS(diffSec);
    }

    const elapsedSec = Math.max(0, Math.floor((now.getTime() - startedAt.getTime()) / 1000) - totalPaused);
    return formatHHMMSS(elapsedSec);
  };

  const formatHHMMSS = (totalSeconds: number) => {
    const hours = String(Math.floor(totalSeconds / 3600)).padStart(2, '0');
    const minutes = String(Math.floor((totalSeconds % 3600) / 60)).padStart(2, '0');
    const seconds = String(totalSeconds % 60).padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  };

  const handleStartSessionSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedArena || !startModalStation || !selectedPlanId) return;
    if (!hasPermission('session.start')) {
      setActionError('You do not have permission to start sessions.');
      return;
    }

    setSubmitting(true);
    try {
      const sessionId = crypto.randomUUID();
      await startSessionRPC({
        arenaId: selectedArena.id,
        sessionId,
        stationId: startModalStation.id,
        billingPlanId: selectedPlanId,
        playerCount,
      });
      setStartModalStation(null);
      await loadFloorData();
    } catch (err: unknown) {
      const message =
        err && typeof err === 'object' && 'message' in err
          ? String((err as { message: unknown }).message)
          : 'Failed to start session';
      setActionError(message);
    } finally {
      setSubmitting(false);
    }
  };

  const handlePause = async (sessionId: string) => {
    if (!selectedArena) return;
    if (!hasPermission('session.pause')) {
      setActionError('You do not have permission to pause sessions.');
      return;
    }
    try {
      await pauseSessionRPC(selectedArena.id, sessionId);
      await loadFloorData();
    } catch (err: unknown) {
      const message =
        err && typeof err === 'object' && 'message' in err
          ? String((err as { message: unknown }).message)
          : 'Pause failed';
      setActionError(message);
    }
  };

  const handleResume = async (sessionId: string) => {
    if (!selectedArena) return;
    if (!hasPermission('session.resume')) {
      setActionError('You do not have permission to resume sessions.');
      return;
    }
    try {
      await resumeSessionRPC(selectedArena.id, sessionId);
      await loadFloorData();
    } catch (err: unknown) {
      const message =
        err && typeof err === 'object' && 'message' in err
          ? String((err as { message: unknown }).message)
          : 'Resume failed';
      setActionError(message);
    }
  };

  const handleStop = async (sessionId: string, memberName?: string) => {
    if (!selectedArena) return;
    if (!hasPermission('session.stop')) {
      setActionError('You do not have permission to stop sessions.');
      return;
    }
    try {
      await stopSessionRPC(selectedArena.id, sessionId);
      await loadFloorData();
      if (hasPermission('payment.create')) {
        setCheckout({
          orderId: crypto.randomUUID(),
          sessionId,
          memberName,
        });
      }
    } catch (err: unknown) {
      const message =
        err && typeof err === 'object' && 'message' in err
          ? String((err as { message: unknown }).message)
          : 'Stop failed';
      setActionError(message);
    }
  };

  return (
    <div>
      {actionError && (
        <div
          style={{
            background: 'rgba(255, 68, 68, 0.12)',
            border: '1px solid var(--danger)',
            borderRadius: '8px',
            padding: '12px',
            marginBottom: '16px',
            color: 'var(--danger)',
            fontSize: '13px',
          }}
        >
          {actionError}
        </div>
      )}
      {/* Top Toolbar — zone chips only when 2+ zones (pilot single-zone UX). */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '20px', gap: '12px' }}>
        {showZoneFilters ? (
          <div style={{ display: 'flex', gap: '8px', background: 'var(--surface)', padding: '4px', borderRadius: '10px', border: '1px solid var(--card-border)', overflowX: 'auto', maxWidth: '100%' }}>
            <button
              type="button"
              onClick={() => setSelectedZoneId(null)}
              style={{
                background: selectedZoneId === null ? primaryColor : 'transparent',
                color: selectedZoneId === null ? '#07070A' : 'var(--text-muted)',
                border: 'none',
                padding: '6px 14px',
                borderRadius: '6px',
                fontWeight: 700,
                fontSize: '12px',
                cursor: 'pointer',
                fontFamily: 'var(--font-heading)',
                whiteSpace: 'nowrap',
              }}
            >
              ALL ZONES ({snapshot.stations.length})
            </button>
            {snapshot.zones.map((zone) => (
              <button
                type="button"
                key={zone.id}
                onClick={() => setSelectedZoneId(zone.id)}
                style={{
                  background: selectedZoneId === zone.id ? primaryColor : 'transparent',
                  color: selectedZoneId === zone.id ? '#07070A' : 'var(--text-muted)',
                  border: 'none',
                  padding: '6px 14px',
                  borderRadius: '6px',
                  fontWeight: 700,
                  fontSize: '12px',
                  cursor: 'pointer',
                  fontFamily: 'var(--font-heading)',
                  whiteSpace: 'nowrap',
                }}
              >
                {zone.name.toUpperCase()}
              </button>
            ))}
          </div>
        ) : (
          <div />
        )}

        <div style={{ display: 'flex', alignItems: 'center', gap: '12px', flexShrink: 0 }}>
          <button
            type="button"
            onClick={() => setShowUnbilled(true)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              background: 'var(--surface)',
              padding: '6px 12px',
              borderRadius: '8px',
              border: '1px solid var(--card-border)',
              cursor: 'pointer',
              color: 'inherit',
            }}
          >
            <ShoppingCart size={16} style={{ color: snapshot.unbilled_sessions.length > 0 ? 'var(--warning)' : 'var(--text-muted)' }} />
            <span style={{ fontSize: '12px', fontWeight: 600 }}>
              UNBILLED QUEUE:{' '}
              <strong style={{ color: snapshot.unbilled_sessions.length > 0 ? 'var(--warning)' : 'var(--text-primary)' }}>
                {snapshot.unbilled_sessions.length}
              </strong>
            </span>
          </button>

          <button type="button" onClick={() => void loadFloorData()} style={{ background: 'var(--surface)', border: '1px solid var(--card-border)', color: 'var(--text-primary)', padding: '8px', borderRadius: '8px', cursor: 'pointer' }}>
            <RefreshCw size={16} />
          </button>
        </div>
      </div>

      {/* Stations Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: '16px' }}>
        {filteredStations.map((station) => {
          const activeSession = snapshot.live_sessions.find((s) => s.station_id === station.id);
          const stateText = deriveStationState(station, activeSession);
          const timerText = calculateFormattedTimer(activeSession);

          let borderColor = 'var(--card-border)';
          let badgeBg = 'rgba(255,255,255,0.08)';
          let badgeColor = 'var(--text-muted)';

          if (stateText === 'LIVE') {
            borderColor = primaryColor;
            badgeBg = 'rgba(124, 255, 79, 0.15)';
            badgeColor = primaryColor;
          } else if (stateText === 'ENDING') {
            borderColor = 'var(--warning)';
            badgeBg = 'rgba(255, 176, 32, 0.15)';
            badgeColor = 'var(--warning)';
          } else if (stateText === 'OVERTIME') {
            borderColor = 'var(--danger)';
            badgeBg = 'rgba(255, 68, 68, 0.2)';
            badgeColor = 'var(--danger)';
          } else if (stateText === 'PAUSED') {
            borderColor = 'var(--info)';
            badgeBg = 'rgba(77, 163, 255, 0.15)';
            badgeColor = 'var(--info)';
          }

          return (
            <div
              key={station.id}
              style={{
                background: 'var(--surface)',
                border: `1px solid ${borderColor}`,
                borderRadius: '12px',
                padding: '16px',
                display: 'flex',
                flexDirection: 'column',
                justifyContent: 'space-between',
                height: '160px',
                position: 'relative',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <span style={{ fontFamily: 'var(--font-heading)', fontWeight: 700, fontSize: '15px' }}>{station.name}</span>
                <span style={{ fontSize: '10px', fontWeight: 700, padding: '3px 8px', borderRadius: '4px', background: badgeBg, color: badgeColor }}>
                  {stateText}
                </span>
              </div>

              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '22px', fontWeight: 700, color: stateText === 'OVERTIME' ? 'var(--danger)' : 'var(--text-primary)', margin: '12px 0' }}>
                {timerText}
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '8px' }}>
                {stateText === 'IDLE' && hasPermission('session.start') && (
                  <button
                    onClick={() => {
                      setStartModalStation(station);
                      if (snapshot.billing_plans.length > 0) setSelectedPlanId(snapshot.billing_plans[0].id);
                    }}
                    className="btn-cyber"
                    style={{ padding: '6px 12px', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '4px' }}
                  >
                    <Play size={12} /> START
                  </button>
                )}

                {(stateText === 'LIVE' || stateText === 'ENDING' || stateText === 'OVERTIME') && activeSession && (
                  <>
                    {hasPermission('session.pause') && (
                      <button
                        onClick={() => void handlePause(activeSession.id)}
                        style={{ background: 'rgba(77, 163, 255, 0.15)', color: 'var(--info)', border: '1px solid var(--info)', padding: '6px', borderRadius: '6px', cursor: 'pointer' }}
                        title="Pause"
                      >
                        <Pause size={14} />
                      </button>
                    )}
                    {hasPermission('session.stop') && (
                      <button
                        onClick={() => void handleStop(activeSession.id, activeSession.member_name)}
                        style={{ background: 'rgba(255, 68, 68, 0.15)', color: 'var(--danger)', border: '1px solid var(--danger)', padding: '6px', borderRadius: '6px', cursor: 'pointer' }}
                        title="Stop Session"
                      >
                        <Square size={14} />
                      </button>
                    )}
                  </>
                )}

                {stateText === 'PAUSED' && activeSession && (
                  <>
                    {hasPermission('session.resume') && (
                      <button
                        onClick={() => void handleResume(activeSession.id)}
                        style={{ background: 'rgba(124, 255, 79, 0.15)', color: primaryColor, border: `1px solid ${primaryColor}`, padding: '6px', borderRadius: '6px', cursor: 'pointer' }}
                        title="Resume"
                      >
                        <Play size={14} />
                      </button>
                    )}
                    {hasPermission('session.stop') && (
                      <button
                        onClick={() => void handleStop(activeSession.id, activeSession.member_name)}
                        style={{ background: 'rgba(255, 68, 68, 0.15)', color: 'var(--danger)', border: '1px solid var(--danger)', padding: '6px', borderRadius: '6px', cursor: 'pointer' }}
                        title="Stop Session"
                      >
                        <Square size={14} />
                      </button>
                    )}
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Start Session Modal */}
      {startModalStation && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.7)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 300 }}>
          <div style={{ width: '100%', maxWidth: '440px', background: 'var(--surface)', border: '1px solid var(--card-border)', borderRadius: '14px', padding: '24px' }}>
            <h3 style={{ fontFamily: 'var(--font-heading)', fontSize: '18px', marginBottom: '16px' }}>START SESSION — {startModalStation.name}</h3>

            <form onSubmit={handleStartSessionSubmit}>
              <div style={{ marginBottom: '16px' }}>
                <label style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '6px', fontFamily: 'var(--font-mono)' }}>
                  SELECT BILLING PLAN
                </label>
                <select
                  value={selectedPlanId}
                  onChange={(e) => setSelectedPlanId(e.target.value)}
                  style={{ width: '100%', padding: '10px', background: 'var(--card)', border: '1px solid var(--card-border)', borderRadius: '8px', color: 'var(--text-primary)' }}
                >
                  {snapshot.billing_plans.map((bp) => (
                    <option key={bp.id} value={bp.id}>
                      {bp.name} ({bp.price} {selectedArena?.currency || ''})
                    </option>
                  ))}
                </select>
              </div>

              <div style={{ marginBottom: '24px' }}>
                <label style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '6px', fontFamily: 'var(--font-mono)' }}>
                  PLAYER COUNT
                </label>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <button type="button" onClick={() => setPlayerCount(Math.max(1, playerCount - 1))} className="btn-cyber-outline">
                    -
                  </button>
                  <span style={{ fontSize: '18px', fontWeight: 700 }}>{playerCount}</span>
                  <button type="button" onClick={() => setPlayerCount(playerCount + 1)} className="btn-cyber-outline">
                    +
                  </button>
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px' }}>
                <button type="button" onClick={() => setStartModalStation(null)} className="btn-cyber-outline">
                  CANCEL
                </button>
                <button type="submit" disabled={submitting} className="btn-cyber">
                  {submitting ? 'STARTING...' : 'START SESSION'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {showUnbilled && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.7)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 350 }}>
          <div style={{ width: '100%', maxWidth: '480px', background: 'var(--surface)', border: '1px solid var(--card-border)', borderRadius: '14px', padding: '24px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '16px' }}>
              <h3 style={{ fontFamily: 'var(--font-heading)', margin: 0 }}>UNBILLED SESSIONS</h3>
              <button type="button" onClick={() => setShowUnbilled(false)} className="btn-cyber-outline">
                CLOSE
              </button>
            </div>
            {snapshot.unbilled_sessions.length === 0 ? (
              <p style={{ color: 'var(--text-muted)' }}>Queue is clear.</p>
            ) : (
              snapshot.unbilled_sessions.map((row) => (
                <div
                  key={row.id}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    padding: '12px 0',
                    borderBottom: '1px solid rgba(255,255,255,0.06)',
                  }}
                >
                  <div>
                    <div style={{ fontWeight: 600 }}>{row.station_name}</div>
                    <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>{row.member_name || 'Walk-in'}</div>
                  </div>
                  {hasPermission('payment.create') && (
                    <button
                      type="button"
                      className="btn-cyber"
                      onClick={() => {
                        setShowUnbilled(false);
                        setCheckout({
                          orderId: row.open_order_id || crypto.randomUUID(),
                          sessionId: row.id,
                          memberName: row.member_name,
                        });
                      }}
                    >
                      BILL
                    </button>
                  )}
                </div>
              ))
            )}
          </div>
        </div>
      )}

      {checkout && (
        <CheckoutPanel
          orderId={checkout.orderId}
          sessionId={checkout.sessionId}
          memberName={checkout.memberName}
          onClose={() => setCheckout(null)}
          onSettled={() => {
            void loadFloorData();
          }}
        />
      )}
    </div>
  );
};
