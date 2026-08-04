import React, { useState } from 'react';
import { supabase } from '../services/supabase';
import { mapAuthError } from '../services/device';

/** Owner / manager web sign-in — light back-office chrome from HTML W login. */
export const Login: React.FC = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setErrorMessage(null);
    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (error) throw error;
    } catch (err: unknown) {
      setErrorMessage(mapAuthError(err));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: '#F4F5F8',
        padding: 32,
        fontFamily: "'Barlow', sans-serif",
        color: '#15171C',
      }}
    >
      <div style={{ width: '100%', maxWidth: 420, display: 'flex', flexDirection: 'column', gap: 22 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <span
            style={{
              fontFamily: "'JetBrains Mono', monospace",
              fontSize: 9.5,
              letterSpacing: '0.14em',
              color: 'rgba(21,23,28,0.45)',
            }}
          >
            OWNER & MANAGER SIGN-IN
          </span>
          <span style={{ fontWeight: 700, fontSize: 28, letterSpacing: '-0.02em' }}>404 Arena</span>
          <span style={{ fontSize: 14, color: '#8A909C' }}>Back office · manage sessions, stock and reports</span>
        </div>

        <form
          onSubmit={handleLogin}
          style={{
            padding: '22px 24px',
            borderRadius: 12,
            background: '#FFFFFF',
            border: '1px solid #E5E7EC',
            boxShadow: '0 1px 2px rgba(16,24,40,.04)',
            display: 'flex',
            flexDirection: 'column',
            gap: 14,
          }}
        >
          {errorMessage ? (
            <div
              style={{
                background: '#FCF3F3',
                border: '1px solid #F0D3D3',
                borderRadius: 8,
                padding: 12,
                color: '#C34141',
                fontSize: 13,
              }}
            >
              {errorMessage}
            </div>
          ) : null}

          <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <span
              style={{
                fontFamily: "'JetBrains Mono', monospace",
                fontSize: 10,
                letterSpacing: '0.1em',
                color: '#A2A7B2',
              }}
            >
              EMAIL
            </span>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="owner@arena.com"
              style={{
                height: 42,
                padding: '0 13px',
                borderRadius: 9,
                border: '1px solid #E5E7EC',
                background: '#F7F8FA',
                fontSize: 14,
                outline: 'none',
              }}
            />
          </label>

          <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <span
              style={{
                fontFamily: "'JetBrains Mono', monospace",
                fontSize: 10,
                letterSpacing: '0.1em',
                color: '#A2A7B2',
              }}
            >
              PASSWORD
            </span>
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              style={{
                height: 42,
                padding: '0 13px',
                borderRadius: 9,
                border: '1px solid #E5E7EC',
                background: '#F7F8FA',
                fontSize: 14,
                outline: 'none',
              }}
            />
          </label>

          <button
            type="submit"
            disabled={loading}
            style={{
              all: 'unset',
              cursor: loading ? 'wait' : 'pointer',
              textAlign: 'center',
              height: 46,
              borderRadius: 9,
              background: '#4C4DDC',
              color: '#FFFFFF',
              fontSize: 13.5,
              fontWeight: 600,
              marginTop: 4,
              opacity: loading ? 0.7 : 1,
            }}
          >
            {loading ? 'Signing in…' : 'Sign in to back office'}
          </button>
        </form>
      </div>
    </div>
  );
};
