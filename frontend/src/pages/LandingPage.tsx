import { useState } from 'react'
import LoginButton from '../components/LoginButton'
import { type AuthResponse } from '../lib/api'
import './landing.css'

interface LandingPageProps {
  onLogin: (response: AuthResponse) => void
  onSkip?: () => void
}

export default function LandingPage({ onLogin, onSkip }: LandingPageProps) {
  const [error, setError] = useState<string | null>(null)

  return (
    <div className="landing">
      {/* ── Hero ── */}
      <section className="landing-hero">
        {/* Animated flame background */}
        <div className="landing-glow" />

        {/* Logo */}
        <div className="landing-logo">
          <svg viewBox="0 0 32 32" className="landing-flame">
            <defs>
              <linearGradient id="flame" x1="0.5" y1="1" x2="0.5" y2="0">
                <stop offset="0%" stopColor="#c07a3e" />
                <stop offset="50%" stopColor="#e0a060" />
                <stop offset="100%" stopColor="#f0c878" />
              </linearGradient>
            </defs>
            <path
              d="M16 2 C16 2 10 10 10 18 C10 22.4 12.7 26 16 26 C19.3 26 22 22.4 22 18 C22 10 16 2 16 2Z"
              fill="url(#flame)"
            />
            <ellipse cx="14" cy="18" rx="1.5" ry="2" fill="#2c2720" opacity="0.8" />
            <ellipse cx="18" cy="18" rx="1.5" ry="2" fill="#2c2720" opacity="0.8" />
            <path d="M13 22 Q16 24 19 22" stroke="#2c2720" strokeWidth="0.8" fill="none" opacity="0.6" />
          </svg>
        </div>

        <h1 className="landing-title">
          Kalcifer
        </h1>
        <p className="landing-subtitle">
          AI-Powered Flow Orchestration
        </p>
        <p className="landing-desc">
          აშენე, გაანალიზე და მართე ავტომატიზაციის ფლოუები
          ბუნებრივი ენით. კალციფერი — შენი სახლის ცეცხლი.
        </p>

        {/* Auth */}
        <div className="landing-auth">
          <LoginButton onLogin={onLogin} onError={setError} />

          {error && (
            <div className="landing-error">
              {error}
            </div>
          )}

          {onSkip && (
            <button className="landing-skip" onClick={onSkip}>
              Demo რეჟიმში გაგრძელება →
            </button>
          )}
        </div>
      </section>

      {/* ── Features ── */}
      <section className="landing-features">
        <div className="landing-feature-grid">
          <FeatureCard
            icon="💬"
            title="AI ჩათი"
            desc="უთხარი რა გინდა ბუნებრივი ენით — კალციფერი ააშენებს ფლოუს შენს ნაცვლად."
          />
          <FeatureCard
            icon="⚡"
            title="ვიზუალური ედიტორი"
            desc="Drag-drop ნაბიჯები, real-time სიმულაცია, ცოცხალი მონიტორინგი."
          />
          <FeatureCard
            icon="🧠"
            title="29 ნაბიჯი"
            desc="ემაილი, SMS, webhook, AI ფიქრი, პარალელური ამოცანები, sub-flow."
          />
          <FeatureCard
            icon="📊"
            title="ანალიტიკა"
            desc="ნაბიჯ-ნაბიჯ conversion rate, საშუალო დრო, funnel ანალიზი."
          />
          <FeatureCard
            icon="🔐"
            title="მრავალ-მოიჯარე"
            desc="Google OAuth, API key, rate limiting, audit log."
          />
          <FeatureCard
            icon="🔥"
            title="საბჭოს ფლოუ"
            desc="მრავალ-პერსონალიანი AI deliberation — ოცნებისმყრელი, რეალისტი, სკეპტიკოსი."
          />
        </div>
      </section>

      {/* ── How it works ── */}
      <section className="landing-how">
        <h2 className="landing-section-title">როგორ მუშაობს</h2>
        <div className="landing-steps">
          <Step num={1} title="ესაუბრე" desc="უთხარი კალციფერს რა გინდა — ის გაიგებს." />
          <div className="landing-step-arrow">→</div>
          <Step num={2} title="ააშენე" desc="ფლოუ ვიზუალურად ჩნდება. შეცვალე, გატესტე." />
          <div className="landing-step-arrow">→</div>
          <Step num={3} title="გაუშვი" desc="აქტივაცია — მონიტორინგი real-time." />
        </div>
      </section>

      {/* ── Footer ── */}
      <footer className="landing-footer">
        <div className="landing-footer-flame">
          <svg viewBox="0 0 32 32" width="20" height="20">
            <path
              d="M16 2 C16 2 10 10 10 18 C10 22.4 12.7 26 16 26 C19.3 26 22 22.4 22 18 C22 10 16 2 16 2Z"
              fill="#c07a3e"
              opacity="0.5"
            />
          </svg>
        </div>
        <span>Kalcifer — Flow Orchestration Engine</span>
      </footer>
    </div>
  )
}

function FeatureCard({ icon, title, desc }: { icon: string; title: string; desc: string }) {
  return (
    <div className="landing-feature-card">
      <div className="landing-feature-icon">{icon}</div>
      <h3 className="landing-feature-title">{title}</h3>
      <p className="landing-feature-desc">{desc}</p>
    </div>
  )
}

function Step({ num, title, desc }: { num: number; title: string; desc: string }) {
  return (
    <div className="landing-step">
      <div className="landing-step-num">{num}</div>
      <h3 className="landing-step-title">{title}</h3>
      <p className="landing-step-desc">{desc}</p>
    </div>
  )
}
