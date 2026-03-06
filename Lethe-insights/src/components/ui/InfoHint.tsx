import { useState, useRef, useEffect, useCallback, useLayoutEffect, type CSSProperties } from 'react';

export interface InfoHintProps {
  title: string;
  body: string[];
  /** Optional "Data source: …" footer */
  source?: string;
}

const VIEWPORT_PAD = 12;
const GAP = 6;
const POP_WIDTH = 300;

export function InfoHint({ title, body, source }: InfoHintProps) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const popRef = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null);

  const toggle = useCallback(() => setOpen(v => !v), []);

  // Close on ESC / click-outside
  useEffect(() => {
    if (!open) return;

    function handleKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false);
    }

    function handleClickOutside(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }

    document.addEventListener('keydown', handleKey);
    document.addEventListener('mousedown', handleClickOutside);
    return () => {
      document.removeEventListener('keydown', handleKey);
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [open]);

  // Collision-aware positioning
  const reposition = useCallback(() => {
    const trigger = rootRef.current;
    const pop = popRef.current;
    if (!trigger || !pop) return;

    const tr = trigger.getBoundingClientRect();
    const popH = pop.offsetHeight;
    const vw = window.innerWidth;
    const vh = window.innerHeight;

    // Horizontal: prefer left-aligned with trigger; flip to right-anchored if overflow
    let left = tr.left;
    if (left + POP_WIDTH > vw - VIEWPORT_PAD) {
      left = tr.right - POP_WIDTH;
    }
    // Still overflowing left edge? Clamp.
    if (left < VIEWPORT_PAD) {
      left = VIEWPORT_PAD;
    }

    // Vertical: prefer below trigger; flip above if overflow
    let top = tr.bottom + GAP;
    if (top + popH > vh - VIEWPORT_PAD) {
      top = tr.top - GAP - popH;
    }
    // Still overflowing top? Clamp to top pad.
    if (top < VIEWPORT_PAD) {
      top = VIEWPORT_PAD;
    }

    setPos({ top, left });
  }, []);

  // Compute position on open + after first paint so popRef has dimensions
  useLayoutEffect(() => {
    if (!open) { setPos(null); return; }
    // Needs a frame so the popover has rendered and we can measure it
    const raf = requestAnimationFrame(reposition);
    return () => cancelAnimationFrame(raf);
  }, [open, reposition]);

  // Recompute on scroll/resize while open
  useEffect(() => {
    if (!open) return;
    window.addEventListener('resize', reposition);
    window.addEventListener('scroll', reposition, true);
    return () => {
      window.removeEventListener('resize', reposition);
      window.removeEventListener('scroll', reposition, true);
    };
  }, [open, reposition]);

  return (
    <div ref={rootRef} style={s.root}>
      <button
        type="button"
        style={s.button}
        onClick={toggle}
        aria-label={`Info: ${title}`}
      >
        i
      </button>

      {open && (
        <div
          ref={popRef}
          style={{
            ...s.popover,
            ...(pos
              ? { position: 'fixed', top: pos.top, left: pos.left }
              : { visibility: 'hidden' as const }),
          }}
        >
          <div style={s.popTitle}>{title}</div>
          <ul style={s.list}>
            {body.map((line, i) => (
              <li key={i} style={s.item}>{line}</li>
            ))}
          </ul>
          {source && <div style={s.source}>Data source: {source}</div>}
        </div>
      )}
    </div>
  );
}

const s: Record<string, CSSProperties> = {
  root: {
    position: 'relative',
    display: 'inline-flex',
    alignItems: 'center',
  },
  button: {
    width: 17,
    height: 17,
    borderRadius: '50%',
    border: '1px solid rgba(255,255,255,0.15)',
    background: 'rgba(255,255,255,0.04)',
    color: 'rgba(255,255,255,0.4)',
    fontSize: 10,
    fontWeight: 700,
    fontStyle: 'italic',
    cursor: 'pointer',
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 0,
    lineHeight: 1,
    flexShrink: 0,
    transition: 'border-color 120ms',
  },
  popover: {
    position: 'fixed',
    zIndex: 9999,
    width: POP_WIDTH,
    padding: '12px 14px',
    background: 'rgba(18,18,26,0.97)',
    border: '1px solid rgba(255,255,255,0.1)',
    borderRadius: 8,
    boxShadow: '0 8px 32px rgba(0,0,0,0.5)',
    backdropFilter: 'blur(12px)',
  },
  popTitle: {
    fontSize: 12,
    fontWeight: 700,
    color: 'rgba(255,255,255,0.85)',
    marginBottom: 6,
  },
  list: {
    margin: 0,
    padding: '0 0 0 14px',
    listStyle: 'disc',
  },
  item: {
    fontSize: 11,
    lineHeight: '1.5',
    color: 'rgba(255,255,255,0.6)',
    marginBottom: 2,
  },
  source: {
    marginTop: 8,
    fontSize: 9,
    color: 'rgba(255,255,255,0.3)',
    borderTop: '1px solid rgba(255,255,255,0.06)',
    paddingTop: 6,
  },
};
