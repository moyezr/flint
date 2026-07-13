import { Contact } from "./components/landing/contact";
import { DemoSection } from "./components/landing/demo-section";
import { Footer } from "./components/landing/footer";
import { Hero } from "./components/landing/hero";
import { Pricing } from "./components/landing/pricing";
import { Principles } from "./components/landing/principles";
import { TypingSection } from "./components/landing/typing-section";
import { ValuePropositions } from "./components/landing/value-propositions";

export default function Home() {
  return (
    <main className="bg-paper text-ink">
      <Hero />
      <DemoSection />
      <ValuePropositions />
      <TypingSection />
      <Principles />
      <Pricing />
      <Contact />
      <div className="bg-deep"><Footer /></div>
    </main>
  );
}
