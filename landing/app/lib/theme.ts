const baseThemes = ["warm", "slate"] as const;

export type BaseTheme = (typeof baseThemes)[number];

export const defaultBaseTheme: BaseTheme = "warm";

export function resolveBaseTheme(value = process.env.NEXT_PUBLIC_FLINT_BASE_THEME): BaseTheme {
  return baseThemes.includes(value as BaseTheme) ? (value as BaseTheme) : defaultBaseTheme;
}
