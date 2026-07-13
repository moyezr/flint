import DotGrid from "@/components/DotGrid";
import { Contact } from "@/components/landing/contact";
import { DemoSection } from "@/components/landing/demo-section";
import { Footer } from "@/components/landing/footer";
import { Hero } from "@/components/landing/hero";
import { Pricing } from "@/components/landing/pricing";
import { Principles } from "@/components/landing/principles";
import { TypingSection } from "@/components/landing/typing-section";
import { ValuePropositions } from "@/components/landing/value-propositions";

export default function Home() {
  return (
    <main className="bg-paper text-ink w-full relative h-full">
      <div className="absolute inset-0 w-full h-full" >
        <DotGrid
          dotSize={5}
          gap={15}
          baseColor="rgba(245, 73, 0, 0.1)"
          activeColor="rgba(245, 73, 0, 1)"
          proximity={120}
          shockRadius={250}
          shockStrength={5}
          resistance={750}
          returnDuration={1.5}

        />
      </div>

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
