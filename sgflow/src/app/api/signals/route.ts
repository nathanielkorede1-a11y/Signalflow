import { NextRequest,NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getAdminClient } from "@/lib/supabase/admin";
import { isDemo } from "@/lib/http";
export const dynamic="force-dynamic";
export async function GET(_req:NextRequest){
 try{
  const supabase=await createClient();const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.json({error:"Authentication required"},{status:401});
  const admin=getAdminClient();const {data:profile}=await admin.from("profiles").select("plan").eq("id",user.id).maybeSingle();const plan=profile?.plan||"free";
  const dayStart=new Date();dayStart.setUTCHours(0,0,0,0);
  const {count}=await admin.from("signal_access").select("id",{count:"exact",head:true}).eq("user_id",user.id).gte("accessed_at",dayStart.toISOString());
  const limit=plan==="premium"?5:1;let signals:any[]=[];
  if(plan==="premium") {const {data,error}=await admin.from("signals").select("id,symbol,direction,entry,stop_loss,take_profit,rr,status,published_at").eq("is_published",true).order("published_at",{ascending:false}).limit(5);if(error)throw error;signals=data||[];}
  else if((count||0)>0){const {data:access,error}=await admin.from("signal_access").select("signal_id,signals(id,symbol,direction,entry,stop_loss,take_profit,rr,status,published_at)").eq("user_id",user.id).gte("accessed_at",dayStart.toISOString()).not("signal_id","is",null).limit(1);if(error)throw error;signals=(access||[]).map((a:any)=>a.signals).filter(Boolean);}
  return NextResponse.json({signals,plan,dailyLimit:limit,usedToday:count||0,remaining:Math.max(0,limit-(count||0))});
 }catch(e){if(isDemo())return NextResponse.json({demo:true,signals:[],plan:"free",dailyLimit:1,usedToday:0,remaining:1});console.error(e);return NextResponse.json({error:"Unable to load signals"},{status:500})}
}
