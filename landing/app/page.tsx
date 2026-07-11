const capabilityRows = [
  ["01", "Hold to speak", "Start with the shortcut. Release when the sentence is done."],
  ["02", "Keep it local", "Audio and transcription stay on your Mac, where they belong."],
  ["03", "Land at the cursor", "Your words return to the field that already has your attention."],
];

const waveBars = [
  25, 36, 54, 70, 44, 82, 58, 34, 64, 91, 52, 76, 42, 61, 86, 47, 32, 68, 57, 78, 40, 65,
  30, 51, 73, 43, 60, 88, 49, 37, 69, 55, 80, 46, 28, 58, 71, 39, 63, 84, 50, 35, 66, 45,
];

function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <span className={compact ? "brand-mark brand-mark-compact" : "brand-mark"}>
      FLINT<span aria-hidden="true">/</span>
    </span>
  );
}

function Waveform() {
  return (
    <div className="waveform" role="img" aria-label="An animated Flint audio waveform">
      <div className="waveform-topline">
        <BrandMark compact />
        <span>LIVE LOCAL SIGNAL</span>
      </div>
      <div className="waveform-bars" aria-hidden="true">
        {waveBars.map((height, index) => (
          <span
            key={index}
            style={
              {
                "--wave-height": `${height}%`,
                "--wave-delay": `${(index % 11) * -0.12}s`,
              } as React.CSSProperties
            }
          />
        ))}
      </div>
      <div className="waveform-bottomline">
        <span className="wave-status"><i aria-hidden="true" /> READY WHEN YOU ARE</span>
        <span>00:00:00</span>
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <main id="top">
      <section className="hero" aria-labelledby="hero-title">
        <nav className="navigation page-shell" aria-label="Primary navigation">
          <a className="wordmark" href="#top" aria-label="Flint home">
            <BrandMark />
          </a>
          <a className="nav-link" href="#availability">
            FOR MACOS
          </a>
        </nav>

        <div className="hero-copy page-shell">
          <p className="eyebrow">LOCAL DICTATION FOR MAC</p>
          <h1 id="hero-title">
            Your voice has a <span>cursor.</span>
          </h1>
          <p className="hero-statement">Speak naturally. Keep writing.</p>
          <p className="hero-detail">
            Flint turns your voice into polished text exactly where your cursor is, without routing your work
            through a subscription service.
          </p>
        </div>

        <div className="hero-wave page-shell">
          <Waveform />
        </div>

        <div className="hero-meta page-shell">
          <span>01 / 03</span>
          <span>VOICE IN, WORDS OUT</span>
        </div>
      </section>

      <section className="capabilities" aria-labelledby="capabilities-title">
        <div className="page-shell section-intro">
          <p className="eyebrow">THE FLINT RHYTHM</p>
          <h2 id="capabilities-title">Less interface. More flow.</h2>
          <p>Flint is designed to disappear into the work you were already doing.</p>
        </div>
        <div className="capability-list page-shell">
          {capabilityRows.map(([index, title, detail]) => (
            <article className="capability" key={index}>
              <span className="capability-index">{index}</span>
              <h3>{title}</h3>
              <p>{detail}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="proof" aria-labelledby="proof-title">
        <div className="page-shell proof-inner">
          <div className="proof-copy">
            <p className="eyebrow">BUILT FOR THE CURSOR</p>
            <h2 id="proof-title">One gesture.<br />No context switch.</h2>
            <p>
              Draft in a document, answer in a browser, enter a command, or write a message. Flint stays small
              and gets out of the way.
            </p>
          </div>
          <div className="cursor-stage" role="img" aria-label="A Flint dictation indicator delivering words to a cursor">
            <div className="cursor-stage-topline">
              <span>THE ACTIVE FIELD</span>
              <BrandMark compact />
            </div>
            <div className="cursor-line"><span>Words, right where you need them</span><i aria-hidden="true" /></div>
            <div className="flint-indicator" aria-hidden="true">
              <b />
              <span />
              <span />
              <span />
              <span />
              <span />
            </div>
          </div>
        </div>
      </section>

      <section className="availability" id="availability" aria-labelledby="availability-title">
        <div className="page-shell availability-inner">
          <p className="eyebrow">COMING TO MACOS</p>
          <h2 id="availability-title"><BrandMark /> for the way you work.</h2>
          <p>Release availability will appear here when the signed Flint disk image is ready.</p>
        </div>
      </section>

      <footer className="footer page-shell">
        <BrandMark compact />
        <span>LOCAL FIRST / MACOS</span>
      </footer>
    </main>
  );
}
