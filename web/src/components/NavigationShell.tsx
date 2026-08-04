import React, { useEffect, useMemo } from 'react';
import { useAuth } from '../context/AuthContext';
import { BranchSelector } from './BranchSelector';
import { registerDevice } from '../services/device';
import { Banknote, LogOut, Monitor, ShieldOff } from 'lucide-react';

interface NavigationShellProps {
  children: React.ReactNode;
}

/**
 * Permission-derived chrome. Only production modules appear in nav —
 * unfinished Owner Web modules are omitted (Epic 4 / M2), not stubbed.
 */
export const NavigationShell: React.FC<NavigationShellProps> = ({ children }) => {
  const { user, selectedArena, hasPermission, signOut, error } = useAuth();

  const primaryColor = selectedArena?.branding.primary_color || '#7CFF4F';
  const canFloor = hasPermission('session.view') || hasPermission('station.view');
  const canShift = hasPermission('shift.view');

  useEffect(() => {
    if (!selectedArena?.id) return;
    if (!selectedArena.permissions.includes('station.view')) return;
    void registerDevice(selectedArena.id).catch(() => {
      // Telemetry must not block entry; server still enforces ops.
    });
  }, [selectedArena?.id, selectedArena?.permissions]);

  const body = useMemo(() => {
    if (error) {
      return (
        <div
          style={{
            background: 'rgba(255, 68, 68, 0.12)',
            border: '1px solid var(--danger)',
            borderRadius: '12px',
            padding: '24px',
            maxWidth: '520px',
            margin: '40px auto',
            color: 'var(--danger)',
          }}
        >
          {error}
        </div>
      );
    }
    if (!canFloor && !canShift) {
      return (
        <div
          style={{
            background: 'var(--surface)',
            border: '1px solid var(--card-border)',
            borderRadius: '12px',
            padding: '40px',
            textAlign: 'center',
            maxWidth: '480px',
            margin: '40px auto',
          }}
        >
          <ShieldOff size={40} style={{ color: primaryColor, marginBottom: '16px' }} />
          <h3 style={{ fontFamily: 'var(--font-heading)', fontSize: '18px', marginBottom: '8px' }}>
            NO PERMITTED MODULES
          </h3>
          <p style={{ fontSize: '14px', color: 'var(--text-muted)' }}>
            Your role on <strong>{selectedArena?.name}</strong> does not include an enabled
            production module. Ask a manager to grant access or switch branch.
          </p>
        </div>
      );
    }
    return children;
  }, [canFloor, canShift, children, error, primaryColor, selectedArena?.name]);

  return (
    <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', background: 'var(--bg)' }}>
      <header
        style={{
          height: '64px',
          background: 'var(--surface)',
          borderBottom: '1px solid var(--card-border)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '0 24px',
          position: 'sticky',
          top: 0,
          zIndex: 100,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '20px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <div
              style={{
                width: '34px',
                height: '34px',
                borderRadius: '8px',
                background: 'rgba(124, 255, 79, 0.12)',
                border: `1px solid ${primaryColor}`,
                color: primaryColor,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontFamily: 'var(--font-heading)',
                fontWeight: 700,
                fontSize: '14px',
                boxShadow: `0 0 12px ${primaryColor}40`,
              }}
            >
              AOS
            </div>
            <div>
              <div style={{ fontFamily: 'var(--font-heading)', fontWeight: 700, fontSize: '15px', letterSpacing: '0.08em' }}>
                {selectedArena?.branding.brand_name || 'ARENA OS'}
              </div>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '10px', color: 'var(--text-muted)', letterSpacing: '0.1em' }}>
                OWNER DASHBOARD
              </div>
            </div>
          </div>

          <BranchSelector />
        </div>

        <div style={{ display: 'flex', background: 'rgba(255, 255, 255, 0.04)', padding: '4px', borderRadius: '10px', border: '1px solid var(--card-border)' }}>
          {canFloor && (
            <button
              type="button"
              style={{
                background: primaryColor,
                color: '#07070A',
                border: 'none',
                padding: '8px 16px',
                borderRadius: '7px',
                fontFamily: 'var(--font-heading)',
                fontWeight: 700,
                fontSize: '13px',
                cursor: 'default',
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
              }}
            >
              <Monitor size={15} /> LIVE FLOOR
            </button>
          )}
          {canShift && (
            <button
              type="button"
              onClick={() => document.getElementById('shift-panel')?.scrollIntoView({ behavior: 'smooth' })}
              style={{
                background: canFloor ? 'transparent' : primaryColor,
                color: canFloor ? 'var(--text-muted)' : '#07070A',
                border: 'none',
                padding: '8px 16px',
                borderRadius: '7px',
                fontFamily: 'var(--font-heading)',
                fontWeight: 700,
                fontSize: '13px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
              }}
            >
              <Banknote size={15} /> SHIFT
            </button>
          )}
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontSize: '13px', fontWeight: 600 }}>{user?.display_name || 'Staff User'}</div>
            <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Role: {selectedArena?.role.name || 'Staff'}</div>
          </div>
          <button
            type="button"
            onClick={() => void signOut()}
            title="Sign Out"
            style={{
              background: 'transparent',
              border: '1px solid var(--card-border)',
              borderRadius: '8px',
              color: 'var(--text-muted)',
              padding: '8px',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
            }}
          >
            <LogOut size={16} />
          </button>
        </div>
      </header>

      <main style={{ flex: 1, padding: '24px' }}>{body}</main>
    </div>
  );
};
