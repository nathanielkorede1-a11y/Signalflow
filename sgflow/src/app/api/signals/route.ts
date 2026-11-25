import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getAdminClient } from "@/lib/supabase/admin";
export const dynamic = "force-dynamic";
export async function GET(_req: NextRequest) {
  try {
    const sb = await createClient();
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return NextResponse.json({ error: "Authentication required" }, { status: 401 });
    const admin = getAdminClient();
    const { data: profile, error: profileError } = await admin.from("profiles").select("plan").eq("id", user.id).maybeSingle();
    if (profileError) throw profileError;
    const plan = profile?.plan === "premium" ? "premium" : "free";
    const { data: usage, error: usageError } = await admin.from("daily_signal_usage").select("used").eq("user_id", user.id).eq("usage_day", new Date().toISOString().slice(0, 10)).maybeSingle();
    if (usageError) throw usageError;
    const usedToday = usage?.used ?? 0;
    const dailyLimit = plan === "premium" ? 5 : 1;
    const { data: accesses, error } = await admin.from("signal_access").select("signal_id,accessed_at,signals(id,symbol,direction,entry,stop_loss,take_profit,rr,status,published_at)").eq("user_id", user.id).gte("accessed_at", new Date(new Date().toISOString().slice(0,10)+"T00:00:00.000Z").toISOString()).order("accessed_at", { ascending: false }).limit(5);
    if (error) throw error;
    const signals = (accesses ?? []).map((a: any) => ({...a.signals, accessed_at:a.accessed_at})).filter((s: any) => s?.id);
    return NextResponse.json({ signals, plan, dailyLimit, usedToday, remaining: Math.max(0,dailyLimit-usedToday), adRequired: plan === "free" });
  } catch (e) { console.error("Signal feed failed", e); return NextResponse.json({ error: "Unable to load signals" }, { status: 500 }); }
}
export async function POST() {
  try {
    const sb = await createClient();
    const { data: { user } } = await sb.auth.getUser();
    if (!user) return NextResponse.json({ error: "Authentication required" }, { status: 401 });
    const admin = getAdminClient();
    const { data, error } = await admin.rpc("grant_premium_signal_access", { p_user_id: user.id });
    if (error) throw error;
    if (!data?.ok) return NextResponse.json({ error: data?.reason ?? "Access unavailable" }, { status: 409 });
    return NextResponse.json({ ok: true, signalId: data.signal_id, usedToday: data.used, remaining: Math.max(0,5-(data.used ?? 0)) });
  } catch (e) { console.error("Premium signal access failed", e); return NextResponse.json({ error: "Unable to grant signal access" }, { status: 500 }); }
}
