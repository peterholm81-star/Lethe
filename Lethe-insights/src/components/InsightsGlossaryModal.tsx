import { useEffect, useCallback } from 'react';

interface GlossaryEntry {
  term: string;
  definition: string;
}

const glossaryEntries: GlossaryEntry[] = [
  { term: 'Sessions', definition: 'Antall anonyme app-åpninger (DAU-ish).' },
  { term: 'Pages Loaded', definition: 'Antall ganger feeden hentet en ny side (page_fetch).' },
  { term: 'Pages / Session', definition: 'Pages Loaded delt på Sessions.' },
  { term: 'Post Attempts', definition: 'Antall forsøk på å poste (post_attempt).' },
  { term: 'Posts', definition: 'Antall vellykkede poster (post_success).' },
  { term: 'Posts / Session', definition: 'Posts delt på Sessions.' },
  { term: 'Ads Shown', definition: 'Antall ganger en ad-card faktisk ble vist (ad_shown).' },
  { term: 'Continued After Ad', definition: 'Sessions som hadde page_fetch etter første ad_shown (innen 10 min).' },
  { term: 'Dropped After Ad', definition: 'Sessions som så ad men ikke hadde page_fetch etterpå.' },
  { term: 'Continue Rate', definition: 'Continued After Ad / Sessions with Ads.' },
  { term: 'Feed View', definition: 'Når feeden åpnes (feed_view).' },
  { term: 'Mode', definition: 'World / Near me / Somewhere.' },
];

interface InsightsGlossaryModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function InsightsGlossaryModal({ isOpen, onClose }: InsightsGlossaryModalProps) {
  // Handle ESC key
  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (e.key === 'Escape') {
      onClose();
    }
  }, [onClose]);

  useEffect(() => {
    if (isOpen) {
      document.addEventListener('keydown', handleKeyDown);
      document.body.style.overflow = 'hidden';
    }
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
      document.body.style.overflow = '';
    };
  }, [isOpen, handleKeyDown]);

  if (!isOpen) return null;

  // Handle backdrop click
  const handleBackdropClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  };

  return (
    <div className="glossary-backdrop" onClick={handleBackdropClick}>
      <div className="glossary-modal" role="dialog" aria-modal="true" aria-labelledby="glossary-title">
        <header className="glossary-header">
          <h2 id="glossary-title" className="glossary-title">Insights Glossary</h2>
          <button 
            className="glossary-close-btn" 
            onClick={onClose}
            aria-label="Close glossary"
          >
            ×
          </button>
        </header>
        
        <div className="glossary-content">
          <dl className="glossary-list">
            {glossaryEntries.map((entry) => (
              <div key={entry.term} className="glossary-entry">
                <dt className="glossary-term">{entry.term}</dt>
                <dd className="glossary-definition">{entry.definition}</dd>
              </div>
            ))}
          </dl>
        </div>
      </div>
    </div>
  );
}
