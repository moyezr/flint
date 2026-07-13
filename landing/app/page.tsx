import Image from "next/image";

import { spaceGrotesk } from "./fonts";
import { TypingTest } from "./typing-test";

const waveBars = [
  28, 45, 64, 31, 73, 52, 87, 40, 59, 78, 44, 68, 35, 82, 55, 91, 46, 70, 34, 62, 84, 51,
  76, 38, 58, 86, 47, 67, 30, 80, 54, 72, 42, 89, 49, 64, 37, 77, 56, 33, 83, 45, 69, 52,
];

const valuePoints = [
  ["Time returns to you", "Say the first draft while the thought is still intact. Flint writes it in the field you already chose."],
  ["Your voice gets clearer", "Turning a thought into a sentence out loud is a small practice. Over time, you hear what is worth saying."],
  ["The work stays yours", "Audio is transcribed on your Mac. Your words never need to become someone else’s training data."],
];

const planDetails = [
  "Local transcription on your Mac",
  "Push to talk at any cursor",
  "Fast, balanced, or accurate models",
  "Private vocabulary and cleanup modes",
  "One active Mac at a time",
];

function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <span className={`${compact ? "brand-mark brand-mark-compact" : "brand-mark"} ${spaceGrotesk.className}`}>
      FLINT<span aria-hidden="true">/</span>
    </span>
  );
}

function WaveField() {
  return (
    <div className="wave-field" aria-hidden="true">
      <div className="wave-field-bars">
        {waveBars.map((height, index) => (
          <span
            key={index}
            style={
              {
                "--wave-height": `${height}%`,
                "--wave-delay": `${(index % 9) * -0.16}s`,
              } as React.CSSProperties
            }
          />
        ))}
      </div>
      <span className="wave-field-orbit wave-field-orbit-one" />
      <span className="wave-field-orbit wave-field-orbit-two" />
    </div>
  );
}

function DemoSurface() {
  return (
    <div className="demo-surface" role="img" aria-label="Flint dictation interface preview">
      <div className="demo-surface-topline">
        <span>FLINT / RECORDING</span>
        <span>00:18</span>
      </div>
      <div className="demo-surface-center">
        <Image src="/flint-mark.png" alt="" width={96} height={96} priority />
        <div className="demo-meter">
          {Array.from({ length: 17 }).map((_, index) => <i key={index} />)}
        </div>
      </div>
      <div className="demo-surface-bottomline">
        <span><b /> LOCAL PROCESSING</span>
        <span>RIGHT OPTION</span>
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <main id="top">
      <section className="hero" aria-labelledby="hero-title">
        <WaveField />
        <nav className="navigation page-shell" aria-label="Primary navigation">
          <a className="wordmark" href="#top" aria-label="Flint home"><BrandMark /></a>
          <a className="nav-link" href="#typing-test">TAKE THE TEST</a>
        </nav>
        <div className="hero-content page-shell">
          <p className="eyebrow">LOCAL DICTATION FOR MAC</p>
          <h1 className={spaceGrotesk.className} id="hero-title">Speak the thought.<br /><span>Keep the flow.</span></h1>
          <p className="hero-tagline">Flint places your voice exactly where your cursor already is.</p>
          <a className="hero-link" href="#typing-test">See your typing gap <span aria-hidden="true">↓</span></a>
        </div>
        <div className="hero-footnote page-shell"><span>PRIVATE BY DESIGN</span><span>MACOS 14+</span></div>
      </section>

      <section className="demo-section section-space" aria-labelledby="demo-title">
        <div className="section-heading page-shell">
          <p className="eyebrow">THE MOMENT IT CLICKS</p>
          <h2 className={spaceGrotesk.className} id="demo-title">Your hands can stay<br />on the work.</h2>
          <p>Hold your shortcut. Speak. Release. Flint takes care of the space between thought and text.</p>
        </div>
        <div className="page-shell demo-wrap"><DemoSurface /></div>
      </section>

      <section className="value-section section-space" aria-labelledby="value-title">
        <div className="section-heading page-shell section-heading-centered">
          <p className="eyebrow">THE BETTER DEFAULT</p>
          <h2 className={spaceGrotesk.className} id="value-title">You have better things<br />to do than type everything.</h2>
        </div>
        <div className="value-list page-shell">
          {valuePoints.map(([title, detail]) => (
            <article className="value-point" key={title}>
              <span className="value-reticle" aria-hidden="true"><i /></span>
              <h3 className={spaceGrotesk.className}>{title}</h3>
              <p>{detail}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="typing-section section-space" id="typing-test" aria-labelledby="typing-title">
        <div className="section-heading page-shell section-heading-centered">
          <p className="eyebrow">A 15-SECOND REALITY CHECK</p>
          <h2 className={spaceGrotesk.className} id="typing-title">You might not need Flint.<br /><span>Let your fingers decide.</span></h2>
          <p>Type one short passage. See how much time your current pace asks from you every day.</p>
        </div>
        <div className="page-shell"><TypingTest /></div>
      </section>

      <section className="principles-section section-space" aria-labelledby="principles-title">
        <div className="principles-intro page-shell">
          <p className="eyebrow">WHY IT FEELS DIFFERENT</p>
          <h2 className={spaceGrotesk.className} id="principles-title">Built to disappear<br />into your day.</h2>
        </div>
        <div className="principles-grid page-shell">
          <article><span>LOCAL</span><h3 className={spaceGrotesk.className}>Offline, by default.</h3><p>Your audio and transcription stay on your Mac after the model is ready.</p></article>
          <article><span>FOCUSED</span><h3 className={spaceGrotesk.className}>One gesture.</h3><p>No workspace, no new editor, no context switch. Just your current cursor.</p></article>
          <article><span>OWNED</span><h3 className={spaceGrotesk.className}>One-time investment.</h3><p>Buy the tool, keep the workflow. There is no monthly meter on your words.</p></article>
        </div>
      </section>

      <section className="pricing-section section-space" id="pricing" aria-labelledby="pricing-title">
        <div className="page-shell pricing-layout">
          <div className="pricing-copy">
            <p className="eyebrow">EARLY ACCESS</p>
            <h2 className={spaceGrotesk.className} id="pricing-title">One purchase.<br />No recurring ask.</h2>
            <p>Flint is being prepared as a direct Mac download. Early access includes the full local dictation workflow and future product updates.</p>
          </div>
          <div className="pricing-detail">
            <p className="pricing-label">FLINT FOR MAC</p>
            <p className={`pricing-value ${spaceGrotesk.className}`}>ONE-TIME</p>
            <ul>
              {planDetails.map((detail) => <li key={detail}>{detail}</li>)}
            </ul>
            <p className="pricing-note">Personal adaptation is on the roadmap. It is not part of the current release.</p>
          </div>
        </div>
      </section>

      <section className="contact-section" aria-labelledby="contact-title">
        <div className="page-shell contact-inner">
          <p className="eyebrow">MAKE ROOM FOR THE THOUGHT</p>
          <h2 className={spaceGrotesk.className} id="contact-title">Want Flint on your Mac?</h2>
          <a className={`contact-link ${spaceGrotesk.className}`} href="mailto:moyezrabbani.work@gmail.com?subject=Flint%20early%20access">moyezrabbani.work@gmail.com <span aria-hidden="true">↗</span></a>
          <p>Early access, questions, and feedback go directly to Moyez.</p>
        </div>
      </section>

      <footer className="footer page-shell">
        <BrandMark compact />
        <span>LOCAL FIRST / MACOS</span>
      </footer>
    </main>
  );
}
