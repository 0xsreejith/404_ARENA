import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { useAuth } from '../../context/AuthContext';
import { BranchSelector } from '../BranchSelector';
import { registerDevice } from '../../services/device';
import {
  OWNER_DARK,
  OWNER_LIGHT,
  RANGE_LABELS,
  SCREEN_META,
  applyOwnerCssVars,
  type DateRange,
  type OwnerScreen,
  type OwnerTokens,
} from '../../theme/tokens';
import { expiringMembers, lowStockProducts } from '../../data/ownerFixtures';

type OwnerNavContextValue = {
  screen: OwnerScreen;
  setScreen: (s: OwnerScreen) => void;
  range: DateRange;
  cycleRange: () => void;
  dark: boolean;
  toggleDark: () => void;
  T: OwnerTokens;
  selectedMemberId: string | null;
  openMember: (id: string) => void;
  toast: (msg: string, meta?: string) => void;
};

const OwnerNavContext = createContext<OwnerNavContextValue | null>(null);

export function useOwnerNav() {
  const ctx = useContext(OwnerNavContext);
  if (!ctx) throw new Error('useOwnerNav requires OwnerShell');
  return ctx;
}

const RANGES: DateRange[] = ['today', 'week', 'month', 'quarter'];

type NavItem = { id: OwnerScreen; label: string; badge?: string; warn?: boolean };
type NavGroup = { label: string; items: NavItem[] };

interface OwnerShellProps {
  children: React.ReactNode;
}

export const OwnerShell: React.FC<OwnerShellProps> = ({ children }) => {
  const { user, selectedArena, hasPermission, signOut, error } = useAuth();
  const [screen, setScreen] = useState<OwnerScreen>('dash');
  const [range, setRange] = useState<DateRange>('today');
  const [dark, setDark] = useState(false);
  const [selectedMemberId, setSelectedMemberId] = useState<string | null>(null);
  const [toastMsg, setToastMsg] = useState<{ msg: string; meta?: string } | null>(null);

  const T = dark ? OWNER_DARK : OWNER_LIGHT;

  useEffect(() => {
    applyOwnerCssVars(T);
    document.documentElement.dataset.owTheme = dark ? 'dark' : 'light';
  }, [T, dark]);

  useEffect(() => {
    if (!selectedArena?.id) return;
    if (!selectedArena.permissions.includes('station.view')) return;
    void registerDevice(selectedArena.id).catch(() => undefined);
  }, [selectedArena?.id, selectedArena?.permissions]);

  const toast = useCallback((msg: string, meta?: string) => {
    setToastMsg({ msg, meta });
    window.setTimeout(() => setToastMsg(null), 2800);
  }, []);

  const cycleRange = useCallback(() => {
    setRange((r) => RANGES[(RANGES.indexOf(r) + 1) % RANGES.length]);
  }, []);

  const openMember = useCallback((id: string) => {
    setSelectedMemberId(id);
    setScreen('member');
  }, []);

  const expCount = expiringMembers().length;
  const lowStock = lowStockProducts().length;
  const unbilled = 1;

  const groups: NavGroup[] = useMemo(() => {
    const ops: NavItem[] = [
      { id: 'sessions', label: 'Sessions' },
      { id: 'members', label: 'Members' },
      { id: 'plans', label: 'Memberships', badge: expCount ? String(expCount) : undefined, warn: expCount > 0 },
    ];
    if (hasPermission('shift.view')) ops.push({ id: 'shift', label: 'Shift' });

    const admin: NavItem[] = [
      { id: 'stations', label: 'Stations' },
      { id: 'staff', label: 'Staff & roles' },
      { id: 'integrations', label: 'Integrations' },
      { id: 'settings', label: 'Settings' },
    ];
    if (hasPermission('session.view') || hasPermission('station.view')) {
      admin.unshift({ id: 'live', label: 'Live floor' });
    }

    return [
      {
        label: 'OVERVIEW',
        items: [
          { id: 'dash', label: 'Dashboard' },
          { id: 'reports', label: 'Reports' },
        ],
      },
      { label: 'OPERATIONS', items: ops },
      {
        label: 'CATALOGUE',
        items: [
          { id: 'games', label: 'Games' },
          { id: 'products', label: 'Inventory', badge: lowStock ? String(lowStock) : undefined, warn: lowStock > 0 },
        ],
      },
      {
        label: 'MONEY',
        items: [{ id: 'expenses', label: 'Expenses', badge: unbilled ? String(unbilled) : undefined, warn: unbilled > 0 }],
      },
      { label: 'ADMIN', items: admin },
    ];
  }, [expCount, hasPermission, lowStock, unbilled]);

  const meta = SCREEN_META[screen];
  const brand = selectedArena?.branding.brand_name || selectedArena?.name || 'Arena';
  const initials = (user?.display_name || 'AK')
    .split(/\s+/)
    .map((p) => p[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

  const path =
    screen === 'member'
      ? 'members/' + (selectedMemberId || '')
      : screen === 'products'
        ? 'inventory'
        : screen === 'plans'
          ? 'memberships'
          : screen;

  const ctx: OwnerNavContextValue = {
    screen,
    setScreen,
    range,
    cycleRange,
    dark,
    toggleDark: () => setDark((d) => !d),
    T,
    selectedMemberId,
    openMember,
    toast,
  };

  return (
    <OwnerNavContext.Provider value={ctx}>
      <div className="ow-app">
        <div className="ow-chrome">
          <div className="ow-chrome-dots">
            <span />
            <span />
            <span />
          </div>
          <div className="ow-chrome-tab">
            <i />
            <span>
              {brand} · Back office
            </span>
          </div>
          <div className="ow-chrome-url">
            <span style={{ color: 'var(--ow-pos)' }}>🔒</span>
            <span>
              manage.arena-os.local/{path}
            </span>
          </div>
          <span style={{ flex: 1 }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <BranchSelector />
            <button type="button" className="ow-tool" onClick={() => void signOut()} style={{ height: 28, padding: '0 10px', fontSize: 11 }}>
              Sign out
            </button>
          </div>
        </div>

        <div className="ow-body">
          <aside className="ow-sidebar">
            <div className="ow-side-brand">
              <span className="ow-side-mark">404</span>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
                <span className="ow-side-name">{brand}</span>
                <span className="ow-side-sub">
                  {(selectedArena?.name || 'Branch')} · {(selectedArena?.role.name || 'owner').toLowerCase()}
                </span>
              </div>
            </div>

            <nav className="ow-side-nav">
              {groups.map((g) => (
                <div key={g.label} className="ow-nav-group">
                  <span className="ow-nav-label">{g.label}</span>
                  {g.items.map((item) => {
                    const on = screen === item.id || (screen === 'member' && item.id === 'members');
                    return (
                      <button
                        key={item.id}
                        type="button"
                        className={`ow-nav-item${on ? ' is-active' : ''}`}
                        onClick={() => setScreen(item.id)}
                      >
                        <span
                          className="ow-nav-dot"
                          style={{ background: on ? 'var(--ow-accent)' : 'var(--ow-fainter)' }}
                        />
                        <span className="ow-nav-text" style={{ fontWeight: on ? 700 : 500, color: on ? 'var(--ow-ink)' : 'var(--ow-ink2)' }}>
                          {item.label}
                        </span>
                        {item.badge ? (
                          <span
                            className="ow-nav-badge"
                            style={{
                              background: item.warn ? 'var(--ow-warnTint)' : 'transparent',
                              color: item.warn ? 'var(--ow-warn)' : 'var(--ow-faint)',
                            }}
                          >
                            {item.badge}
                          </span>
                        ) : null}
                      </button>
                    );
                  })}
                </div>
              ))}
            </nav>

            <div className="ow-side-foot">
              <div className="ow-sync">
                <span className="ow-sync-dot" />
                <div style={{ display: 'flex', flexDirection: 'column', gap: 0, minWidth: 0 }}>
                  <span className="ow-sync-title">Counter tablet online</span>
                  <span className="ow-sync-meta">SYNCED 12s AGO</span>
                </div>
              </div>
              <button type="button" className="ow-side-cta" onClick={() => setScreen('live')}>
                Open counter view
              </button>
            </div>
          </aside>

          <div className="ow-main">
            <header className="ow-top">
              <div style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
                <span className="ow-top-title">{meta[0]}</span>
                <span className="ow-top-sub">{meta[1]}</span>
              </div>
              <span style={{ flex: 1 }} />
              <div className="ow-search">
                <span>Search members, sessions</span>
                <kbd>⌘K</kbd>
              </div>
              <button type="button" className="ow-tool" onClick={cycleRange}>
                {RANGE_LABELS[range]} ▾
              </button>
              <button type="button" className="ow-tool" onClick={() => setDark((d) => !d)}>
                <span
                  style={{
                    width: 11,
                    height: 11,
                    borderRadius: '50%',
                    border: '1.5px solid var(--ow-accent)',
                    background: 'linear-gradient(90deg, var(--ow-accent) 50%, transparent 50%)',
                  }}
                />
                <span>{dark ? 'Dark' : 'Light'}</span>
              </button>
              <button
                type="button"
                className="ow-tool-primary"
                onClick={() => toast('Export queued', 'CSV for ' + RANGE_LABELS[range].toLowerCase())}
              >
                Export
              </button>
              <div className="ow-avatar" title={user?.display_name || ''}>
                {initials}
              </div>
            </header>

            <div className="ow-content ow-fade">
              {error ? (
                <div
                  className="ow-panel"
                  style={{ borderColor: 'var(--ow-dangerBd)', background: 'var(--ow-dangerSoft)', color: 'var(--ow-danger)' }}
                >
                  {error}
                </div>
              ) : (
                children
              )}
            </div>
          </div>
        </div>

        {toastMsg ? (
          <div
            style={{
              position: 'fixed',
              left: '50%',
              bottom: 28,
              transform: 'translateX(-50%)',
              zIndex: 50,
              display: 'flex',
              alignItems: 'center',
              gap: 12,
              padding: '12px 18px',
              borderRadius: 11,
              background: 'var(--ow-ink)',
              color: 'var(--ow-panel)',
              boxShadow: '0 8px 24px var(--ow-shadow2)',
              animation: 'owFade .16s ease-out',
            }}
          >
            <span style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--ow-pos)', flex: 'none' }} />
            <span style={{ fontSize: 14, fontWeight: 600 }}>{toastMsg.msg}</span>
            {toastMsg.meta ? (
              <span className="ow-mono" style={{ fontSize: 11, opacity: 0.55 }}>
                {toastMsg.meta}
              </span>
            ) : null}
          </div>
        ) : null}
      </div>
    </OwnerNavContext.Provider>
  );
};
