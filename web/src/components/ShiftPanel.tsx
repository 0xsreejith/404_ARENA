import React, { useEffect, useState } from 'react';
import { useAuth } from '../context/AuthContext';
import {
  closeShift,
  fetchCurrentShift,
  fetchShiftSummary,
  openShift,
  readableShiftError,
  ShiftRecord,
  ShiftSummary,
} from '../services/shift';
import { formatMoney } from '../services/checkout';
import { RefreshCw } from 'lucide-react';

export const ShiftPanel: React.FC = () => {
  const { selectedArena, hasPermission } = useAuth();
  const [current, setCurrent] = useState<ShiftRecord | null>(null);
  const [summary, setSummary] = useState<ShiftSummary | null>(null);
  const [openingFloat, setOpeningFloat] = useState('');
  const [countedCash, setCountedCash] = useState('');
  const [notes, setNotes] = useState('');
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const currency = selectedArena?.currency || 'INR';
  const primaryColor = selectedArena?.branding.primary_color || '#7CFF4F';

  const load = async () => {
    if (!selectedArena || !hasPermission('shift.view')) return;
    setLoading(true);
    setError(null);
    try {
      const shift = await fetchCurrentShift(selectedArena.id);
      setCurrent(shift);
      setSummary(shift ? await fetchShiftSummary(selectedArena.id, shift.id) : null);
    } catch (err: unknown) {
      setError(readableShiftError(err, 'Failed to load shift'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, [selectedArena?.id]);

  if (!selectedArena || !hasPermission('shift.view')) return null;

  const handleOpen = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!hasPermission('shift.open')) {
      setError('You do not have permission to open shifts.');
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await openShift({
        arenaId: selectedArena.id,
        shiftId: crypto.randomUUID(),
        openingFloat,
        idempotencyKey: `shift-open-${crypto.randomUUID()}`,
      });
      setOpeningFloat('');
      await load();
    } catch (err: unknown) {
      setError(readableShiftError(err, 'Failed to open shift'));
    } finally {
      setSubmitting(false);
    }
  };

  const handleClose = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!current) return;
    if (!hasPermission('shift.close')) {
      setError('You do not have permission to close shifts.');
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await closeShift({
        arenaId: selectedArena.id,
        shiftId: current.id,
        countedCash,
        notes,
        idempotencyKey: `shift-close-${crypto.randomUUID()}`,
      });
      setCountedCash('');
      setNotes('');
      await load();
    } catch (err: unknown) {
      setError(readableShiftError(err, 'Failed to close shift'));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <section id="shift-panel" style={{ marginBottom: '24px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
        <div>
          <h2 style={{ fontFamily: 'var(--font-heading)', fontSize: '18px', margin: 0 }}>SHIFT & CASH</h2>
          <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>
            {current ? `OPEN · ${current.business_date}` : 'NO OPEN SHIFT'}
          </div>
        </div>
        <button type="button" onClick={() => void load()} className="btn-cyber-outline" style={{ display: 'flex', gap: '8px' }}>
          <RefreshCw size={14} /> REFRESH
        </button>
      </div>

      {error && (
        <div style={{ background: 'rgba(255, 68, 68, 0.12)', border: '1px solid var(--danger)', color: 'var(--danger)', borderRadius: '8px', padding: '12px', marginBottom: '12px', fontSize: '13px' }}>
          {error}
        </div>
      )}

      <div style={{ display: 'grid', gridTemplateColumns: 'minmax(260px, 360px) 1fr', gap: '16px' }}>
        <div style={{ background: 'var(--surface)', border: '1px solid var(--card-border)', borderRadius: '14px', padding: '16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '14px' }}>
            <span style={{ width: '10px', height: '10px', borderRadius: '50%', background: current ? primaryColor : 'var(--text-muted)' }} />
            <strong style={{ fontFamily: 'var(--font-heading)' }}>{current ? 'SHIFT OPEN' : 'SHIFT CLOSED'}</strong>
          </div>
          {loading ? (
            <div style={{ color: primaryColor, fontFamily: 'var(--font-mono)' }}>LOADING SHIFT...</div>
          ) : current ? (
            <form onSubmit={handleClose}>
              <Row label="Opening float" value={formatMoney(current.opening_float, currency)} />
              <Row label="Expected cash" value={formatMoney(summary?.expected_cash, currency)} />
              <input value={countedCash} onChange={(e) => setCountedCash(e.target.value)} placeholder={`Counted cash (${currency})`} style={inputStyle} />
              <textarea value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Notes if variance" rows={3} style={{ ...inputStyle, resize: 'vertical' }} />
              {hasPermission('shift.close') && (
                <button type="submit" disabled={submitting} className="btn-cyber-outline" style={{ width: '100%', borderColor: 'var(--danger)', color: 'var(--danger)' }}>
                  {submitting ? 'CLOSING...' : 'CLOSE SHIFT'}
                </button>
              )}
            </form>
          ) : (
            <form onSubmit={handleOpen}>
              <input value={openingFloat} onChange={(e) => setOpeningFloat(e.target.value)} placeholder={`Opening float (${currency})`} style={inputStyle} />
              {hasPermission('shift.open') && (
                <button type="submit" disabled={submitting} className="btn-cyber" style={{ width: '100%' }}>
                  {submitting ? 'OPENING...' : 'OPEN SHIFT'}
                </button>
              )}
            </form>
          )}
        </div>

        <div style={{ background: 'var(--surface)', border: '1px solid var(--card-border)', borderRadius: '14px', padding: '16px' }}>
          <h3 style={{ margin: '0 0 12px', fontFamily: 'var(--font-heading)', fontSize: '15px' }}>SUMMARY</h3>
          {summary ? (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: '12px' }}>
              <Metric label="Expected cash" value={formatMoney(summary.expected_cash, currency)} highlight />
              <Metric label="Play sales" value={formatMoney(summary.sales.play, currency)} />
              <Metric label="Product sales" value={formatMoney(summary.sales.product, currency)} />
              <Metric label="Discount" value={formatMoney(summary.discount_total, currency)} />
              <Metric label="Tax" value={formatMoney(summary.tax_total, currency)} />
              <Metric label="Cash" value={formatMoney(summary.payments_by_method.cash, currency)} />
              <Metric label="UPI" value={formatMoney(summary.payments_by_method.upi, currency)} />
              <Metric label="Card" value={formatMoney(summary.payments_by_method.card, currency)} />
              <Metric label="Orders" value={String(summary.order_count)} />
              <Metric label="Sessions" value={String(summary.session_count)} />
              <Metric label="Unbilled" value={String(summary.unbilled_session_count)} />
            </div>
          ) : (
            <p style={{ color: 'var(--text-muted)', margin: 0 }}>Open a shift to see live cash reconciliation.</p>
          )}
        </div>
      </div>
    </section>
  );
};

const inputStyle: React.CSSProperties = {
  width: '100%',
  boxSizing: 'border-box',
  marginBottom: '10px',
  padding: '11px',
  background: 'var(--card)',
  border: '1px solid var(--card-border)',
  borderRadius: '8px',
  color: 'var(--text-primary)',
  fontFamily: 'var(--font-mono)',
};

const Row: React.FC<{ label: string; value: string }> = ({ label, value }) => (
  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '10px', fontSize: '13px' }}>
    <span style={{ color: 'var(--text-muted)' }}>{label}</span>
    <span style={{ fontFamily: 'var(--font-mono)', fontWeight: 600 }}>{value}</span>
  </div>
);

const Metric: React.FC<{ label: string; value: string; highlight?: boolean }> = ({ label, value, highlight }) => (
  <div style={{ background: 'rgba(255,255,255,0.04)', borderRadius: '10px', padding: '12px' }}>
    <div style={{ fontSize: '10px', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)', letterSpacing: '0.1em' }}>
      {label.toUpperCase()}
    </div>
    <div style={{ marginTop: '6px', fontFamily: 'var(--font-mono)', fontSize: highlight ? '20px' : '15px', fontWeight: 700, color: highlight ? 'var(--accent)' : 'var(--text-primary)' }}>
      {value}
    </div>
  </div>
);
