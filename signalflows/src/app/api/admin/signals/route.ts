import { NextRequest, NextResponse } from "next/server";
import { timingSafeEqual, createHash } from "crypto";
import { getAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
function authorized(req: NextRequest) {
  const expected = process.env.SIGNALFLOW_ADMIN_SECRET;
  const supplied = req.headers.get("x-signalflow-admin") || "";
  if (!expected) return false;
  return timingSafeEqual(createHash("sha256").update(supplied).digest(), createHash("sha256").update(expected).digest());
}

export async function GET(req: NextRequest) {
  if (!authorized(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  try {
    const { data, error } = await getAdminClient().from("signals").select("*").order("created_at", { ascending: false }).limit(200);
    if (error) throw error;
    return NextResponse.json({ signals: data || [] });
  } catch (error) {
    console.error("Admin signal list failed", error);
    return NextResponse.json({ error: "Unable to load signals" }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  if (!authorized(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  try {
    const body = await req.json();
    const symbol = typeof body.symbol === "string" ? body.symbol.trim().toUpperCase() : "";
    const direction = body.direction;
    const entry = Number(body.entry), stop_loss = Number(body.stop_loss), take_profit = Number(body.take_profit);
    if (!/^[A-Z0-9._-]{2,24}$/.test(symbol) || !["BUY", "SELL"].includes(direction) ||
      ![entry, stop_loss, take_profit].every(n => Number.isFinite(n) && n > 0) ||
      (direction === "BUY" && !(stop_loss < entry && take_profit > entry)) ||
      (direction === "SELL" && !(stop_loss > entry && take_profit < entry))) {
      return NextResponse.json({ error: "Invalid signal fields or price direction" }, { status: 400 });
    }
    const row = {
      external_id: typeof body.external_id === "string" && body.external_id.trim() ? body.external_id.trim() : null,
      symbol, direction, entry, stop_loss, take_profit,
      rr: Number.isFinite(Number(body.rr)) && Number(body.rr) > 0 ? Number(body.rr) : null,
      status: typeof body.status === "string" ? body.status : "active",
      is_published: body.is_published === true,
      published_at: new Date().toISOString()
    };
    const { data, error } = await getAdminClient().from("signals").insert(row).select().single();
    if (error) throw error;
    return NextResponse.json({ signal: data }, { status: 201 });
  } catch (error) {
    console.error("Admin signal creation failed", error);
    return NextResponse.json({ error: "Unable to create signal" }, { status: 500 });
  }
}

export async function PATCH(req: NextRequest) {
  if (!authorized(req)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  try {
    const body = await req.json();
    if (typeof body.id !== "string" || !body.id) return NextResponse.json({ error: "Signal id is required" }, { status: 400 });
    const updates: Record<string, unknown> = {};
    if (typeof body.is_published === "boolean") updates.is_published = body.is_published;
    if (typeof body.status === "string" && ["active", "closed", "tp_hit", "sl_hit", "breakeven", "cancelled"].includes(body.status)) updates.status = body.status;
    if (!Object.keys(updates).length) return NextResponse.json({ error: "No valid updates supplied" }, { status: 400 });
    const { data, error } = await getAdminClient().from("signals").update(updates).eq("id", body.id).select().single();
    if (error) throw error;
    return NextResponse.json({ signal: data });
  } catch (error) {
    console.error("Admin signal update failed", error);
    return NextResponse.json({ error: "Unable to update signal" }, { status: 500 });
  }
}
