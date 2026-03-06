export interface InfoEntry {
  title: string;
  body: string[];
}

export const moodInfo: Record<string, InfoEntry> = {
  aiObserver: {
    title: 'AI Observer',
    body: [
      'Kontinuerlig overvåkning av aggregerte mood-signaler per region.',
      '"Confidence" øker med volum og stabilitet i målingene.',
      'Bygger på buckets/aggregater (ikke rå tekst eller identitet).',
      'Brukes for å se hvor endringene skjer først.',
    ],
  },
  temperatureIndex: {
    title: 'Emotional Temperature',
    body: [
      'En komprimert indeks for regional stemning i valgt tidsvindu.',
      'Positiv/negativ balanse + momentum, normalisert til en skala.',
      'Tolk trend over tid – enkeltpunkter kan være støy ved lavt volum.',
      'Privacy-safe: kun aggregert telling.',
    ],
  },
  liveMap: {
    title: 'Live Emotional Map',
    body: [
      'Visualiserer hvor stemningen er mest positiv/negativ akkurat nå.',
      'Farger = relative nivåer innen valgt scope (region/verdensdel).',
      'Bruk kartet til å finne hotspots og skift – drilldown senere.',
    ],
  },
  stabilityIndex: {
    title: 'Stability Index',
    body: [
      'Måler om signalet holder seg stabilt eller svinger kraftig.',
      'Høy stabilitet = tryggere beslutningsgrunnlag.',
      'Lav stabilitet = mer eksperiment/observasjon før tiltak.',
      'Hjelper å unngå overtolkning.',
    ],
  },
};
