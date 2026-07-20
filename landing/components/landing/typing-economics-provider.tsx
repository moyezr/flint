"use client";

import { createContext, ReactNode, useContext, useMemo, useState } from "react";

import type { TypingEconomicsResult } from "@/lib/typing-economics";

interface TypingEconomicsContextValue {
  result: TypingEconomicsResult | null;
  setResult: (result: TypingEconomicsResult | null) => void;
}

const TypingEconomicsContext = createContext<TypingEconomicsContextValue | null>(null);

export function TypingEconomicsProvider({ children }: { children: ReactNode }) {
  const [result, setResult] = useState<TypingEconomicsResult | null>(null);
  const value = useMemo(() => ({ result, setResult }), [result]);

  return (
    <TypingEconomicsContext.Provider value={value}>
      {children}
    </TypingEconomicsContext.Provider>
  );
}

export function useTypingEconomics() {
  const context = useContext(TypingEconomicsContext);
  if (!context) {
    throw new Error("useTypingEconomics must be used within TypingEconomicsProvider");
  }
  return context;
}
