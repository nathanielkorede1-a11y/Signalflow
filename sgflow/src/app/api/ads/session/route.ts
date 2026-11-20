import { NextResponse } from "next/server";
import { randomUUID } from "crypto";
import { createClient } from "@/lib/supabase/server";
import { getAdminClient } from "@/lib/supabase/admin";
export async function POST(){try{const sb=await createClient();const {data:{user}}=await sb.auth.getUser();if(!user)return NextResponse.json({error:"Authentication required"},{status:401});const admin=getAdminClient();const {data,error}=await admin.from("ad_sessions").insert({user_id:user.id,provider_session_id:randomUUID(),status:"pending",expires_at:new Date(Date.now()+10*60*1000).toISOString()}).select("id,provider_session_id,expires_at").single();if(error)throw error;return NextResponse.json({session:data,adProviderConfigured:Boolean(process.env.AD_PROVIDER_WEBHOOK_SECRET)});}catch(e){console.error(e);return NextResponse.json({error:"Could not start ad session"},{status:500})}}
