export interface InfoEntry {
  title: string;
  body: string[];
}

export const monetizationInfo: Record<string, InfoEntry> = {
  revenueOverview: {
    title: 'Revenue Overview',
    body: [
      'Sanntidsstatus for monetization akkurat nå.',
      'Revenue er estimert fra visninger × eCPM × fill × trigger (kan være testdata).',
      'Bruk dette som "helse"-indikator, ikke som regnskap.',
    ],
  },
  countryOptimization: {
    title: 'Country Monetization Optimization',
    body: [
      'Motoren: foreslår landspesifikke ad-policyer basert på signaler.',
      'Målet er å øke inntekt uten å skade vekst (trafikk, retention).',
      'Handlinger kan simuleres før de brukes.',
    ],
  },
  globalSignalRow: {
    title: 'Global Signal Row',
    body: [
      'Kompakt statuslinje for å skanne systemet på 2 sekunder.',
      'Viser footprint, konsentrasjon, ad-pressure og confidence.',
      'Når confidence er lav: ikke ta aggressive beslutninger.',
    ],
  },
  geographicMap: {
    title: 'Geographic Footprint',
    body: [
      'Viser hvor i verden inntekt/aktivitet faktisk skjer.',
      'Brukes til å se konsentrasjon, hull i markedet og nye vekstlommer.',
      'Kartet er et visuelt anker, ikke en detaljrapport.',
    ],
  },
  advancedIntelligence: {
    title: 'Advanced Intelligence',
    body: [
      'Alt "tungt" og forklarende er samlet her for å unngå støy.',
      'Åpne ved behov (investor/diagnose), ellers hold den lukket.',
      'Ingenting her er nødvendig for daglig operasjon.',
    ],
  },
  globalStatus: {
    title: 'Global Status',
    body: [
      'Diagnose av nåværende footprint og risiko.',
      'Forklarer hvorfor monetization er/ikke er bottleneck.',
      'Gir beslutningskontekst, ikke handlinger.',
    ],
  },
  emotionalContext: {
    title: 'Emotional Context',
    body: [
      'Utforsker sammenheng mellom "mood" og monetization.',
      'Aktiveres først når datamengden er høy nok (confidence).',
      'Gir innsikt, men skal ikke styre ad-policy alene.',
    ],
  },
  simulationLab: {
    title: 'Simulation Lab',
    body: [
      'Sandbox for å teste antakelser (eCPM, fill, trigger, drop-rate).',
      'Brukes for sensitivitet: hva påvirker revenue mest?',
      'Flytter ikke policy automatisk – kun beslutningsstøtte.',
    ],
  },
  aiInterpretation: {
    title: 'AI Interpretation',
    body: [
      'Kort narrativ oppsummering av hva tallene antyder.',
      'Bygger på samme signaler som resten av siden.',
      'Ment som kommunikasjon/fortolkning, ikke kilde til sannhet.',
    ],
  },
  topEarningCountries: {
    title: 'Top Earning Countries',
    body: [
      'Rask liste for å se hvilke markeder som bærer inntekten.',
      'Brukes til fokus: hvor vi optimaliserer først.',
      'Bør vurderes sammen med konsentrasjons- og risiko-signaler.',
    ],
  },
};
