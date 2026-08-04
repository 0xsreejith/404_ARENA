import React, { useEffect, useState } from 'react';
import { useAuth } from '../context/AuthContext';
import {
  fetchOrderPreview,
  formatMoney,
  openCheckout,
  OrderPreview,
  settleOrder,
} from '../services/checkout';
import { readableShiftError } from '../services/shift';

interface CheckoutPanelProps {
  orderId: string;
  sessionId?: string;
  memberName?: string;
  onClose: () => void;
  onSettled: () => void;
}

export const CheckoutPanel: React.FC<CheckoutPanelProps> = ({
  orderId,
  sessionId,
  memberName,
  onClose,
  onSettled,
}) => {
  const { selectedArena, hasPermission } = useAuth();
  const [preview, setPreview] = useState<OrderPreview | null>(null);
  const [method, setMethod] = useState<'cash' | 'upi' | 'card'>('cash');
  const [amount, setAmount] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [receipt, setReceipt] = useState<string | null>(null);

  const currency = selectedArena?.currency || 'INR';
  const primaryColor = selectedArena?.branding.primary_color || '#7CFF4F';

  const load = async () => {
    if (!selectedArena) return;
    setLoading(true);
    setError(null);
    try {
      await openCheckout({
        arenaId: selectedArena.id,
        orderId,
        sessionId,
      });
      const data = await fetchOrderPreview(selectedArena.id, orderId);
      setPreview(data);
      setAmount(data.balance_due);
    } catch (err: unknown) {
      const message =
        err && typeof err === 'object' && 'message' in err
          ? String((err as { message: unknown }).message)
          : 'Failed to open checkout';
      setError(message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, [selectedArena?.id, orderId, sessionId]);

  const handleSettle = async () => {
    if (!selectedArena || !hasPermission('payment.create')) {
      setError('You do not have permission to take payments.');
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const result = await settleOrder({
        arenaId: selectedArena.id,
        orderId,
        paymentId: crypto.randomUUID(),
        method,
        amount,
      });
      setReceipt(result.receipt_number || null);
      const data = await fetchOrderPreview(selectedArena.id, orderId);
      setPreview(data);
      onSettled();
    } catch (err: unknown) {
      setError(readableShiftError(err, 'Settle failed'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.72)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 400,
        padding: '24px',
      }}
    >
      <div
        style={{
          width: '100%',
          maxWidth: '640px',
          background: 'var(--surface)',
          border: '1px solid var(--card-border)',
          borderRadius: '14px',
          padding: '24px',
          maxHeight: '90vh',
          overflow: 'auto',
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '16px' }}>
          <div>
            <h3 style={{ fontFamily: 'var(--font-heading)', fontSize: '18px', margin: 0 }}>
              CHECKOUT & BILLING
            </h3>
            {memberName && (
              <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px' }}>{memberName}</div>
            )}
          </div>
          <button
            type="button"
            onClick={onClose}
            style={{
              background: 'transparent',
              border: '1px solid var(--card-border)',
              color: 'var(--text-muted)',
              borderRadius: '8px',
              padding: '6px 12px',
              cursor: 'pointer',
            }}
          >
            CLOSE
          </button>
        </div>

        {error && (
          <div
            style={{
              background: 'rgba(255, 68, 68, 0.12)',
              border: '1px solid var(--danger)',
              color: 'var(--danger)',
              borderRadius: '8px',
              padding: '12px',
              marginBottom: '12px',
              fontSize: '13px',
            }}
          >
            {error}
          </div>
        )}

        {receipt && (
          <div
            style={{
              background: 'rgba(124, 255, 79, 0.12)',
              border: `1px solid ${primaryColor}`,
              borderRadius: '8px',
              padding: '12px',
              marginBottom: '12px',
              color: primaryColor,
              fontFamily: 'var(--font-mono)',
              fontWeight: 700,
            }}
          >
            SETTLED · RECEIPT {receipt}
          </div>
        )}

        {loading && !preview ? (
          <div style={{ color: 'var(--accent)', fontFamily: 'var(--font-mono)', padding: '24px 0' }}>
            LOADING ORDER PREVIEW...
          </div>
        ) : (
          preview && (
            <>
              <div style={{ marginBottom: '16px' }}>
                {preview.items.map((item) => (
                  <div
                    key={item.id}
                    style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      padding: '10px 0',
                      borderBottom: '1px solid rgba(255,255,255,0.06)',
                    }}
                  >
                    <div>
                      <div style={{ fontWeight: 600 }}>{item.name}</div>
                      <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>
                        Qty {item.quantity} @ {formatMoney(item.unit_price, currency)}
                      </div>
                    </div>
                    <div style={{ fontFamily: 'var(--font-mono)', fontWeight: 600 }}>
                      {formatMoney(item.line_total, currency)}
                    </div>
                  </div>
                ))}
              </div>

              <div
                style={{
                  background: 'rgba(255,255,255,0.04)',
                  borderRadius: '10px',
                  padding: '14px',
                  marginBottom: '16px',
                }}
              >
                <Row label="Subtotal" value={formatMoney(preview.subtotal, currency)} />
                <Row label="Discount" value={formatMoney(preview.discount_total, currency)} />
                <Row
                  label={preview.prices_include_tax ? 'Tax (included)' : 'Tax'}
                  value={formatMoney(preview.tax_total, currency)}
                />
                <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: '10px', paddingTop: '10px', borderTop: '1px solid rgba(255,255,255,0.1)' }}>
                  <span style={{ fontFamily: 'var(--font-mono)', fontSize: '10px', letterSpacing: '0.12em', color: 'var(--text-muted)' }}>
                    TOTAL
                  </span>
                  <span style={{ fontFamily: 'var(--font-mono)', fontWeight: 700, fontSize: '28px', color: primaryColor }}>
                    {formatMoney(preview.total, currency)}
                  </span>
                </div>
                <Row label="Balance due" value={formatMoney(preview.balance_due, currency)} />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '8px', marginBottom: '12px' }}>
                {(['cash', 'upi', 'card'] as const).map((m) => (
                  <button
                    key={m}
                    type="button"
                    onClick={() => setMethod(m)}
                    style={{
                      height: '44px',
                      borderRadius: '8px',
                      border: method === m ? `1px solid ${primaryColor}` : '1px solid var(--card-border)',
                      background: method === m ? `${primaryColor}22` : 'transparent',
                      color: method === m ? primaryColor : 'var(--text-muted)',
                      fontFamily: 'var(--font-heading)',
                      fontWeight: 700,
                      cursor: 'pointer',
                      textTransform: 'uppercase',
                    }}
                  >
                    {m}
                  </button>
                ))}
              </div>

              <input
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                disabled={!!receipt}
                style={{
                  width: '100%',
                  padding: '12px',
                  marginBottom: '12px',
                  background: 'var(--card)',
                  border: '1px solid var(--card-border)',
                  borderRadius: '8px',
                  color: 'var(--text-primary)',
                  fontFamily: 'var(--font-mono)',
                }}
              />

              <button
                type="button"
                className="btn-cyber"
                disabled={!!receipt || loading || !hasPermission('payment.create')}
                onClick={() => void handleSettle()}
                style={{ width: '100%', padding: '16px', fontWeight: 700 }}
              >
                TAKE PAYMENT & PRINT
              </button>
            </>
          )
        )}
      </div>
    </div>
  );
};

const Row: React.FC<{ label: string; value: string }> = ({ label, value }) => (
  <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', fontSize: '13px' }}>
    <span style={{ color: 'var(--text-muted)' }}>{label}</span>
    <span style={{ fontFamily: 'var(--font-mono)' }}>{value}</span>
  </div>
);
