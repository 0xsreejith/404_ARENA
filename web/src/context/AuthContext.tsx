import React, { createContext, useContext, useEffect, useState } from 'react';
import { supabase, fetchMeContext, UserProfile, ArenaContext } from '../services/supabase';

interface AuthContextType {
  user: UserProfile | null;
  arenas: ArenaContext[];
  selectedArena: ArenaContext | null;
  loading: boolean;
  error: string | null;
  setSelectedArena: (arena: ArenaContext) => void;
  hasPermission: (permissionCode: string) => boolean;
  signOut: () => Promise<void>;
  refreshContext: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<UserProfile | null>(null);
  const [arenas, setArenas] = useState<ArenaContext[]>([]);
  const [selectedArena, setSelectedArena] = useState<ArenaContext | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const loadUserContext = async () => {
    setLoading(true);
    setError(null);
    try {
      const session = (await supabase.auth.getSession()).data.session;
      if (!session) {
        setUser(null);
        setArenas([]);
        setSelectedArena(null);
        setLoading(false);
        return;
      }

      const meData = await fetchMeContext();
      setUser(meData.user);
      setArenas(meData.arenas);
      if (meData.arenas.length > 0) {
        setSelectedArena((prev) => {
          if (prev) {
            const found = meData.arenas.find((a) => a.id === prev.id);
            return found || meData.arenas[0];
          }
          return meData.arenas[0];
        });
      }
    } catch (err: unknown) {
      const mapped =
        err && typeof err === 'object' && 'message' in err
          ? String((err as { message: unknown }).message)
          : 'Failed to load user session';
      setError(mapped);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadUserContext();

    const { data: authListener } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session) {
        loadUserContext();
      } else {
        setUser(null);
        setArenas([]);
        setSelectedArena(null);
        setLoading(false);
      }
    });

    return () => {
      authListener.subscription.unsubscribe();
    };
  }, []);

  const hasPermission = (code: string): boolean => {
    if (!selectedArena) return false;
    return selectedArena.permissions.includes(code);
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setArenas([]);
    setSelectedArena(null);
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        arenas,
        selectedArena,
        loading,
        error,
        setSelectedArena,
        hasPermission,
        signOut,
        refreshContext: loadUserContext,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
