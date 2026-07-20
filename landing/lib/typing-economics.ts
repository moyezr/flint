export const TYPING_TEST_SECONDS = 15;
export const MINIMUM_REVEAL_CHARACTERS = 15;
export const SPEAKING_PACE_WPM = 130;
export const ASSUMED_TYPING_HOURS_PER_DAY = 1;
export const ASSUMED_TYPING_DAYS_PER_WEEK = 5;
export const CONSERVATIVE_HOURLY_RATE = 20;

interface TypingEconomicsInput {
  charactersTyped: number;
  completedEarly: boolean;
  elapsedSeconds: number;
}

interface MeasuredTypingResult {
  charactersTyped: number;
  measurementSeconds: number;
  wpm: number;
}

export interface InsufficientTypingResult {
  kind: "insufficient";
  charactersTyped: number;
  minimumCharacters: number;
}

export interface NoGapTypingResult extends MeasuredTypingResult {
  kind: "no-gap";
  gap: 0;
  gapPercent: 0;
}

export interface SavingsTypingResult extends MeasuredTypingResult {
  kind: "savings";
  gap: number;
  gapPercent: number;
  monthlyValue: number;
  weeklyHours: number;
  weeklyValue: number;
}

export type TypingEconomicsResult =
  | InsufficientTypingResult
  | NoGapTypingResult
  | SavingsTypingResult;

export function calculateTypingEconomics({
  charactersTyped,
  completedEarly,
  elapsedSeconds,
}: TypingEconomicsInput): TypingEconomicsResult {
  const safeCharacterCount = Math.max(0, Math.floor(charactersTyped));
  if (safeCharacterCount < MINIMUM_REVEAL_CHARACTERS) {
    return {
      kind: "insufficient",
      charactersTyped: safeCharacterCount,
      minimumCharacters: MINIMUM_REVEAL_CHARACTERS,
    };
  }

  const measurementSeconds = completedEarly
    ? Math.max(0.1, elapsedSeconds)
    : TYPING_TEST_SECONDS;
  const wpm = (safeCharacterCount / 5) / (measurementSeconds / 60);
  const gap = Math.max(0, 1 - (wpm / SPEAKING_PACE_WPM));

  if (gap === 0) {
    return {
      kind: "no-gap",
      charactersTyped: safeCharacterCount,
      measurementSeconds,
      wpm,
      gap: 0,
      gapPercent: 0,
    };
  }

  const weeklyHours = ASSUMED_TYPING_HOURS_PER_DAY * ASSUMED_TYPING_DAYS_PER_WEEK * gap;
  const weeklyValue = weeklyHours * CONSERVATIVE_HOURLY_RATE;
  const monthlyValue = weeklyValue * 52 / 12;

  return {
    kind: "savings",
    charactersTyped: safeCharacterCount,
    measurementSeconds,
    wpm,
    gap,
    gapPercent: gap * 100,
    monthlyValue,
    weeklyHours,
    weeklyValue,
  };
}
