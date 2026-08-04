import React from 'react';
import { AuthProvider, useAuth } from './context/AuthContext';
import { Login } from './pages/Login';
import { OwnerShell, useOwnerNav } from './components/owner/OwnerShell';
import { DashboardPage } from './pages/owner/DashboardPage';
import {
  ExpensesPage,
  GamesPage,
  IntegrationsPage,
  InventoryPage,
  MemberRecordPage,
  MembersPage,
  MembershipsPage,
  ReportsPage,
  SessionsPage,
  SettingsPage,
  StaffPage,
  StationsAdminPage,
} from './pages/owner/OwnerPages';
import { LiveFloorGrid } from './components/LiveFloorGrid';
import { ShiftPanel } from './components/ShiftPanel';

const OwnerRouter: React.FC = () => {
  const { screen } = useOwnerNav();
  const { hasPermission } = useAuth();

  switch (screen) {
    case 'dash':
      return <DashboardPage />;
    case 'reports':
      return <ReportsPage />;
    case 'sessions':
      return <SessionsPage />;
    case 'members':
      return <MembersPage />;
    case 'member':
      return <MemberRecordPage />;
    case 'plans':
      return <MembershipsPage />;
    case 'games':
      return <GamesPage />;
    case 'products':
      return <InventoryPage />;
    case 'expenses':
      return <ExpensesPage />;
    case 'stations':
      return <StationsAdminPage />;
    case 'staff':
      return <StaffPage />;
    case 'integrations':
      return <IntegrationsPage />;
    case 'settings':
      return <SettingsPage />;
    case 'live':
      return (hasPermission('session.view') || hasPermission('station.view')) ? (
        <div className="cyber-surface" style={{ padding: 16 }}>
          <LiveFloorGrid />
        </div>
      ) : (
        <DashboardPage />
      );
    case 'shift':
      return hasPermission('shift.view') ? (
        <div className="cyber-surface" style={{ padding: 16 }}>
          <ShiftPanel />
        </div>
      ) : (
        <DashboardPage />
      );
    default:
      return <DashboardPage />;
  }
};

const MainContent: React.FC = () => {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div
        style={{
          minHeight: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: '#F4F5F8',
          color: '#4C4DDC',
          fontFamily: "'JetBrains Mono', monospace",
          fontSize: 12,
          letterSpacing: '0.12em',
        }}
      >
        LOADING BACK OFFICE…
      </div>
    );
  }

  if (!user) {
    return <Login />;
  }

  return (
    <OwnerShell>
      <OwnerRouter />
    </OwnerShell>
  );
};

export const App: React.FC = () => {
  return (
    <AuthProvider>
      <MainContent />
    </AuthProvider>
  );
};
