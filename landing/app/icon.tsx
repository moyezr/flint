import { ImageResponse } from "next/og";

export const size = {
  width: 512,
  height: 512,
};

export const contentType = "image/png";

export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          alignItems: "center",
          background: "#f5f3ef",
          color: "#11110f",
          display: "flex",
          height: "100%",
          justifyContent: "center",
          position: "relative",
          width: "100%",
        }}
      >
        <div
          style={{
            border: "28px solid #11110f",
            display: "flex",
            height: 300,
            width: 300,
          }}
        />
        <span
          style={{
            color: "#f0501d",
            display: "flex",
            fontFamily: "monospace",
            fontSize: 266,
            fontWeight: 800,
            left: 146,
            lineHeight: 1,
            position: "absolute",
            top: 112,
          }}
        >
          F
        </span>
      </div>
    ),
    size,
  );
}
