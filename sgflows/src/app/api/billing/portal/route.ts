import { NextResponse } from "next/server";
import Stripe from "stripe";
import { createClient } from "@/lib/supabase/server";
import { getAdminClient } from "@/lib/supabase/admin";
export async function POST(){
 try{
  const sb=await createClient();const {data:{user}}=await sb.auth.getUser();if(!user)return NextResponse.json({error:"Authentication required"},{status:401});
  if(!process.env.STRIPE_SECRET_KEY||!process.env.NEXT_PUBLIC_APP_URL)return NextResponse.json({error:"Billing is not configured"},{status:503});
  const {data:profile,error}=await getAdminClient().from("profiles").select("stripe_customer_id").eq("id",user.id).maybeSingle();if(error)throw error;
  if(!profile?.stripe_customer_id)return NextResponse.json({error:"No Stripe customer is linked to this account"},{status:404});
  const stripe=new Stripe(process.env.STRIPE_SECRET_KEY);const session=await stripe.billingPortal.sessions.create({customer:profile.stripe_customer_id,return_url:process.env.NEXT_PUBLIC_APP_URL});
  return NextResponse.json({url:session.url});
 }catch(e){console.error("Stripe portal error",e);return NextResponse.json({error:"Unable to open billing portal"},{status:500});}
}
