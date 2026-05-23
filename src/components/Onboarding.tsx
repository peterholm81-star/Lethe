/**
 * Onboarding - 4-screen intro flow for new users
 *
 * Shows once on first launch, persists completion to localStorage.
 * Matches the dark, quiet visual style of the app.
 */

import { useState } from 'react'

interface OnboardingProps {
  onComplete: () => void
}

interface Screen {
  title: string
  body: string
  footer?: string
}

const SCREENS: Screen[] = [
  {
    title: "Why Lethe?",
    body: "In Greek mythology, Lethe was the river of forgetting.\n\nSouls who drank from it lost the memory of their earthly lives.\n\nWe named this app after that river.\nA place where what you say does not follow you.",
    footer: "λήθη — oblivion, concealment, forgetting.",
  },
  {
    title: "Nothing lasts",
    body: "Every confession disappears after approximately 24 hours.\n\nNo history.\nNo archive.\nNo permanent record.\n\nOnly what people were willing to say tonight.",
  },
  {
    title: "No profiles. No identity.",
    body: "There are no usernames.\nNo followers.\nNo public identity.\n\nJust the quiet truth of what people would say\nif nobody remembered it tomorrow.",
  },
  {
    title: "Write where you stand",
    body: "You can read from anywhere in the world.\n\nBut Near Me confessions come from where people actually are.\n\nLocation is used only to place a confession in the world.\nNothing more.",
  },
]

export function Onboarding({ onComplete }: OnboardingProps) {
  const [currentScreen, setCurrentScreen] = useState(0)

  const isLastScreen = currentScreen === SCREENS.length - 1
  const screen = SCREENS[currentScreen]

  function handleContinue() {
    if (isLastScreen) {
      onComplete()
    } else {
      setCurrentScreen((prev) => prev + 1)
    }
  }

  function handleSkip() {
    onComplete()
  }

  return (
    <div className="onboarding-overlay">
      <button className="onboarding-skip" onClick={handleSkip}>
        Skip
      </button>

      <div className="onboarding-content">
        <h2 className="onboarding-title">{screen.title}</h2>
        <p className="onboarding-body">{screen.body}</p>

        {screen.footer && (
          <p className="onboarding-footer">{screen.footer}</p>
        )}

        <div className="onboarding-dots">
          {SCREENS.map((_, index) => (
            <span
              key={index}
              className={`onboarding-dot${index === currentScreen ? ' active' : ''}`}
            />
          ))}
        </div>

        <button className="onboarding-cta" onClick={handleContinue}>
          {isLastScreen ? 'Enter Lethe' : 'Continue'}
        </button>
      </div>
    </div>
  )
}
