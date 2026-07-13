"use client";

import { useState } from "react";

type ConfirmationState = "idle" | "submitting" | "confirmed" | "error";

export function TransferConfirmation({ token }: { token: string }) {
  const [state, setState] = useState<ConfirmationState>(token ? "idle" : "error");
  const [message, setMessage] = useState(token ? "" : "This transfer link is incomplete.");

  async function confirm() {
    setState("submitting");
    setMessage("");
    try {
      const response = await fetch("/api/licenses/transfers/confirm", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ token }),
      });
      const payload = await response.json();
      if (!response.ok) {
        throw new Error(payload.error?.message ?? "The transfer could not be confirmed.");
      }
      setState("confirmed");
      setMessage("Transfer confirmed. Return to Flint on the new Mac to finish activation.");
    } catch (error) {
      setState("error");
      setMessage(error instanceof Error ? error.message : "The transfer could not be confirmed.");
    }
  }

  return (
    <div className="flex flex-col items-start gap-4">
      {state === "confirmed" ? null : (
        <button className="min-h-[46px] cursor-pointer border border-deep bg-deep px-[18px] font-mono text-[13px] font-semibold text-paper disabled:cursor-wait disabled:opacity-60" type="button" onClick={confirm} disabled={state !== "idle"}>
          {state === "submitting" ? "Confirming..." : "Confirm transfer"}
        </button>
      )}
      {message ? <p className="m-0 text-[15px] leading-[1.5] text-muted" role={state === "error" ? "alert" : "status"}>{message}</p> : null}
    </div>
  );
}
