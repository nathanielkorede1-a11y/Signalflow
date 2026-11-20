import { NextRequest, NextResponse } from "next/server";
import { createHmac, timingSafeEqual } from "crypto";
import { getAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  const secret = process.env.AD_PROVIDER_WEBHOOK_SECRET;
  if (!secret) return NextResponse.json({ error: "Ad provider callback is not configured" }, { status: 503 });
  const raw = await req.text();
  const signature = req.headers.get("x-ad-signature") || "";
  const expected = createHmac("sha256", secret).update(raw).digest();
  let supplied: Buffer;
  try { supplied = Buffer.from(signature, "hex"); } catch { supplied = Buffer.alloc(0); }
  if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) {
    return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
  }
  try {
    const body: unknown = JSON.parse(raw);
    if (!body || typeof body !== "object" || !("sessionId" in body) || typeof body.sessionId !== "string" || !("event" in body) || body.event !== "completed") {
      return NextResponse.json({ error: "Invalid callback payload" }, { status: 400 });
    }
    const admin = getAdminClient();
    const { data, error } = await admin.rpc("complete_ad_unlock", { p_provider_session_id: body.sessionId });
    if (error) throw error;
    if (!data?.ok) {
      const status = data?.reason === "no_published_signal" ? 404 : 409;
      return NextResponse.json({ error: data?.reason || "Unlock rejected" }, { status });
    }
    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("Ad callback processing failed", error);
    return NextResponse.json({ error: "Callback processing failed" }, { status: 500 });
  }
}
