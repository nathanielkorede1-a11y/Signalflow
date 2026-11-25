import { NextResponse } from "next/server";
import { randomUUID } from "crypto";
import { createClient } from "@/lib/supabase/server";
import { getAdminClient } from "@/lib/supabase/admin";
export async function POST() {
  try {
    if (!process.env.AD_PROVIDER_WEBHOOK_SECRET || !process.env.AD_PROVIDER_START_URL) return NextResponse.json({ error: "Ad provider is not connected. Configure an approved provider before enabling Free unlocks." }, { status: 503 });
    const sb=await createClient(); const {data:{user}}=await sb.auth.getUser();
    if(!user) return NextResponse.json({error:"Authentication required"},{status:401});
    const admin=getAdminClient();
    const {data:profile}=await admin.from("profiles").select("plan").eq("id",user.id).maybeSingle();
    if(profile?.plan === "premium") return NextResponse.json({error:"Premium accounts do not need ads"},{status:409});
    const provider_session_id=randomUUID();
    const {data,error}=await admin.from("ad_sessions").insert({user_id:user.id,provider_session_id,status:"pending",expires_at:new Date(Date.now()+10*60*1000).toISOString()}).select("id,provider_session_id,expires_at").single();
    if(error) throw error;
    const startUrl=new URL(process.env.AD_PROVIDER_START_URL);
    startUrl.searchParams.set("session_id",provider_session_id);
    startUrl.searchParams.set("callback_url",`${process.env.NEXT_PUBLIC_APP_URL}/api/ads/callback`);
    return NextResponse.json({session:data,adUrl:startUrl.toString()});
  } catch(e) { console.error(e); return NextResponse.json({error:"Could not start ad session"},{status:500}); }
}
