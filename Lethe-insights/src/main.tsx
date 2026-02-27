import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import 'mapbox-gl/dist/mapbox-gl.css'
import './index.css'
import App from './App.tsx'
import { InsightsProvider } from './contexts/InsightsContext'
import { FiltersCoreProvider } from './engine/filters_core'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <InsightsProvider>
      <FiltersCoreProvider>
        <App />
      </FiltersCoreProvider>
    </InsightsProvider>
  </StrictMode>,
)
