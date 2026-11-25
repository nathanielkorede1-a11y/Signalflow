import { NextResponse } from "next/server";
import Stripe from "stripe";
import { createClient } from "@/lib/supabase/server";
export async function POST() {
 try {
  const sb=await createClient(); const {data:{user}}=await sb.auth.getUser();
  if(!user) return NextResponse.json({error:"Authentication required"},{status:401});
  const {STRIPE_SECRET_KEY,STRIPE_PREMIUM_PRICE_ID,NEXT_PUBLIC_APP_URL}=process.env;
  if(!STRIPE_SECRET_KEY||!STRIPE_PREMIUM_PRICE_ID||!NEXT_PUBLIC_APP_URL) return NextResponse.json({error:"Billing is not configured"},{status:503});
  const stripe=new Stripe(STRIPE_SECRET_KEY);
  const session=await stripe.checkout.sessions.create({mode:"subscription",line_items:[{price:STRIPE_PREMIUM_PRICE_ID,quantity:1}],success_url:`${NEXT_PUBLIC_APP_URL}/?billing=success`,cancel_url:`${NEXT_PUBLIC_APP_URL}/?billing=cancelled`,client_reference_id:user.id,customer_email:user.email??undefined,metadata:{supabase_user_id:user.id},subscription_data:{metadata:{supabase_user_id:user.id}},allow_promotion_codes:true});
  return NextResponse.json({url:session.url});
 } catch(e) { console.error("Stripe checkout error",e); return NextResponse.json({error:"Unable to create checkout session"},{status:500}); }
}
