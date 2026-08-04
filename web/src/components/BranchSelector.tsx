import React, { useState } from 'react';
import { useAuth } from '../context/AuthContext';

/** Branch switcher styled for Owner Web light chrome. */
export const BranchSelector: React.FC = () => {
  const { arenas, selectedArena, setSelectedArena } = useAuth();
  const [isOpen, setIsOpen] = useState(false);

  if (!selectedArena) return null;

  if (arenas.length <= 1) {
    return (
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          height: 28,
          padding: '0 10px',
          borderRadius: 7,
          background: 'var(--ow-canvas, #F4F5F8)',
          border: '1px solid var(--ow-bd, #E5E7EC)',
          fontSize: 12,
          fontWeight: 600,
          color: 'var(--ow-ink2, #3D424D)',
        }}
      >
        {selectedArena.branding.brand_name || selectedArena.name}
      </div>
    );
  }

  return (
    <div style={{ position: 'relative' }}>
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        style={{
          all: 'unset',
          cursor: 'pointer',
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          height: 28,
          padding: '0 10px',
          borderRadius: 7,
          background: 'var(--ow-canvas, #F4F5F8)',
          border: '1px solid var(--ow-bd, #E5E7EC)',
          fontSize: 12,
          fontWeight: 600,
          color: 'var(--ow-ink2, #3D424D)',
        }}
      >
        {selectedArena.branding.brand_name || selectedArena.name} ▾
      </button>
      {isOpen ? (
        <div
          style={{
            position: 'absolute',
            top: '100%',
            right: 0,
            marginTop: 6,
            width: 240,
            background: 'var(--ow-panel, #fff)',
            border: '1px solid var(--ow-bd, #E5E7EC)',
            borderRadius: 10,
            padding: 6,
            zIndex: 200,
            boxShadow: '0 8px 24px var(--ow-shadow2, rgba(16,24,40,.2))',
          }}
        >
          {arenas.map((a) => (
            <button
              key={a.id}
              type="button"
              onClick={() => {
                setSelectedArena(a);
                setIsOpen(false);
              }}
              style={{
                all: 'unset',
                cursor: 'pointer',
                display: 'block',
                width: '100%',
                boxSizing: 'border-box',
                padding: '10px 12px',
                borderRadius: 7,
                fontSize: 13,
                fontWeight: a.id === selectedArena.id ? 700 : 500,
                background: a.id === selectedArena.id ? 'var(--ow-accTint, #EEEEFD)' : 'transparent',
                color: 'var(--ow-ink, #15171C)',
              }}
            >
              {a.branding.brand_name || a.name}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
};
