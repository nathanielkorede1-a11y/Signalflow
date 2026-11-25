import { NextRequest, NextResponse } from "next/server";
import { timingSafeEqual, createHash } from "crypto";
import { getAdminClient } from "@/lib/supabase/admin";

function safeEqual(a: string, b: string) {
  return timingSafeEqual(createHash("sha256").update(a).digest(), createHash("sha256").update(b).digest());
}

export async function POST(req: NextRequest) {
  const secret = process.env.MT5_WEBHOOK_SECRET;
  if (!secret) return NextResponse.json({ error: "Webhook is not configured" }, { status: 503 });
  if (!safeEqual(req.headers.get("x-signalflow-secret") || "", secret)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  try {
    const body = await req.json();
    const { symbol, direction, entry, stop_loss, take_profit, rr, status = "active", external_id } = body ?? {};
    const numbers = [entry, stop_loss, take_profit].map(Number);
    if (typeof symbol !== "string" || !/^[A-Za-z0-9._-]{2,24}$/.test(symbol.trim()) ||
      !["BUY", "SELL"].includes(direction) || !numbers.every(Number.isFinite) || numbers.some(n => n <= 0) ||
      typeof external_id !== "string" || external_id.trim().length < 3 || external_id.length > 100 ||
      !["active", "closed", "tp_hit", "sl_hit", "breakeven", "cancelled"].includes(status)) {
      return NextResponse.json({ error: "Invalid signal payload" }, { status: 400 });
    }
    const [entryPrice, stop, target] = numbers;
    if ((direction === "BUY" && !(stop < entryPrice && target > entryPrice)) ||
        (direction === "SELL" && !(stop > entryPrice && target < entryPrice))) {
      return NextResponse.json({ error: "Stop loss and take profit do not match signal direction" }, { status: 400 });
    }
    const admin = getAdminClient();
    const row = {
      external_id: external_id.trim(), symbol: symbol.trim().toUpperCase(), direction,
      entry: entryPrice, stop_loss: stop, take_profit: target,
      rr: Number.isFinite(Number(rr)) && Number(rr) > 0 ? Number(rr) : null,
      status, is_published: true, published_at: new Date().toISOString()
    };
    const { data, error } = await admin.from("signals").upsert(row, { onConflict: "external_id" }).select().single();
    if (error) throw error;
    return NextResponse.json({ ok: true, signal: data }, { status: 200 });
  } catch (error) {
    console.error("MT5 webhook error", error);
    return NextResponse.json({ error: "Could not save signal" }, { status: 500 });
  }
}
