const capabilityRows = [
  ["01", "Hold to speak", "A shortcut that respects the rhythm of writing."],
  ["02", "Keep it local", "Audio and transcription stay on your Mac."],
  ["03", "Land at the cursor", "Works in the places where work already happens."],
];

export default function Home() {
  return (
    <main>
      <section className="hero" aria-labelledby="hero-title">
        <nav className="navigation" aria-label="Primary navigation">
          <a className="wordmark" href="#top" aria-label="Flint home">
            FLINT<span aria-hidden="true">/</span>
          </a>
          <a className="nav-link" href="#availability">
            macOS
          </a>
        </nav>

        <div className="hero-grid" id="top">
          <div className="hero-copy">
            <p className="eyebrow">LOCAL DICTATION FOR MAC</p>
            <h1 id="hero-title">Flint Dictation.</h1>
            <p className="hero-statement">Speak naturally. Keep writing.</p>
            <p className="hero-detail">
              Flint turns your voice into polished text exactly where your cursor is, without routing your
              work through a subscription service.
            </p>
          </div>

          <div className="hero-surface" role="img" aria-label="Placeholder for the Flint application command surface">
            <div className="surface-header">
              <span>FLINT</span>
              <span>LOCAL / READY</span>
            </div>
            <div className="surface-meter" aria-hidden="true">
              {Array.from({ length: 14 }).map((_, index) => (
                <span key={index} style={{ "--bar": `${index}` } as React.CSSProperties} />
              ))}
            </div>
            <div className="surface-cursor" aria-hidden="true" />
          </div>
        </div>

        <div className="hero-rule" aria-hidden="true" />
        <p className="hero-index">01 / 03</p>
      </section>

      <section className="capabilities" aria-labelledby="capabilities-title">
        <div className="section-heading">
          <p className="eyebrow">THE WORKFLOW</p>
          <h2 id="capabilities-title">A quieter way to dictate.</h2>
        </div>
        <div className="capability-list">
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
        <div className="proof-visual" role="img" aria-label="Placeholder for a Flint typing workflow photograph">
          <div className="proof-line proof-line-one" />
          <div className="proof-line proof-line-two" />
          <div className="proof-marker">F</div>
        </div>
        <div className="proof-copy">
          <p className="eyebrow">BUILT FOR THE CURSOR</p>
          <h2 id="proof-title">One gesture. No context switch.</h2>
          <p>
            Draft in a document, answer in a browser, enter a command, or write a message. Flint stays small
            and gets out of the way.
          </p>
        </div>
      </section>

      <section className="availability" id="availability" aria-labelledby="availability-title">
        <p className="eyebrow">COMING TO MACOS</p>
        <h2 id="availability-title">A one-time download. Your Mac. Your words.</h2>
        <p>Release availability will appear here when the signed Flint disk image is ready.</p>
      </section>

      <footer className="footer">
        <span>FLINT</span>
        <span>LOCAL FIRST / MACOS</span>
      </footer>
    </main>
  );
}
