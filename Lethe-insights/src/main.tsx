import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import 'mapbox-gl/dist/mapbox-gl.css'
import './index.css'
import App from './App.tsx'
import { InsightsProvider } from './contexts/InsightsContext'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <InsightsProvider>
      <App />
    </InsightsProvider>
  </StrictMode>,
)
