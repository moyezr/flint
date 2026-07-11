import { ImageResponse } from "next/og";

export const alt = "Flint - Local Dictation for Mac";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          background: "#f5f3ef",
          color: "#11110f",
          display: "flex",
          flexDirection: "column",
          height: "100%",
          justifyContent: "space-between",
          padding: "74px",
          width: "100%",
        }}
      >
        <div style={{ display: "flex", fontFamily: "monospace", fontSize: 28, fontWeight: 700 }}>
          FLINT<span style={{ color: "#f0501d" }}>/</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", maxWidth: 940 }}>
          <span style={{ color: "#f0501d", display: "flex", fontFamily: "monospace", fontSize: 20 }}>
            LOCAL DICTATION FOR MAC
          </span>
          <span style={{ display: "flex", fontSize: 92, fontWeight: 700, letterSpacing: "-4px", marginTop: 24 }}>
            Speak naturally.
          </span>
          <span style={{ display: "flex", fontSize: 92, fontWeight: 700, letterSpacing: "-4px" }}>
            Keep writing.
          </span>
        </div>
        <div style={{ alignItems: "flex-end", display: "flex", gap: 10, height: 54 }}>
          {Array.from({ length: 14 }).map((_, index) => (
            <span
              key={index}
              style={{
                background: index % 2 === 0 ? "#f0501d" : "#11110f",
                display: "flex",
                height: `${24 + index * 2}px`,
                width: "18px",
              }}
            />
          ))}
        </div>
      </div>
    ),
    size,
  );
}
