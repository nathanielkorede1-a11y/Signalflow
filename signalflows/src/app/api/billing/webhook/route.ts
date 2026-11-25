import { NextRequest, NextResponse } from "next/server";
import Stripe from "stripe";
import { getAdminClient } from "@/lib/supabase/admin";
export const runtime = "nodejs";
async function setPlan(subscription: Stripe.Subscription, stripe: Stripe) {
  const admin=getAdminClient();
  let userId=subscription.metadata?.supabase_user_id;
  const customerId=typeof subscription.customer==="string"?subscription.customer:subscription.customer.id;
  if(!userId){const {data}=await admin.from("profiles").select("id").eq("stripe_customer_id",customerId).maybeSingle();userId=data?.id;}
  if(!userId) throw new Error(`No SignalFlow user mapped to Stripe subscription ${subscription.id}`);
  const premium=["active","trialing"].includes(subscription.status);
  const {error}=await admin.from("profiles").update({plan:premium?"premium":"free",stripe_customer_id:customerId,stripe_subscription_id:subscription.id,updated_at:new Date().toISOString()}).eq("id",userId);
  if(error) throw error;
}
export async function POST(req:NextRequest){
 const key=process.env.STRIPE_SECRET_KEY, secret=process.env.STRIPE_WEBHOOK_SECRET;
 if(!key||!secret)return NextResponse.json({error:"Stripe webhook is not configured"},{status:503});
 const stripe=new Stripe(key); let event:Stripe.Event;
 try{event=stripe.webhooks.constructEvent(await req.text(),req.headers.get("stripe-signature")||"",secret);}catch{return NextResponse.json({error:"Invalid webhook signature"},{status:400});}
 const admin=getAdminClient();
 try{
  const {error:claimError}=await admin.from("stripe_events").insert({event_id:event.id,event_type:event.type});
  if(claimError){if(claimError.code==="23505")return NextResponse.json({received:true,duplicate:true});throw claimError;}
  if(event.type.startsWith("customer.subscription.")) await setPlan(event.data.object as Stripe.Subscription,stripe);
  else if(event.type==="checkout.session.completed"){
   const session=event.data.object as Stripe.Checkout.Session;
   if(session.mode==="subscription" && typeof session.subscription==="string"){
    let sub=await stripe.subscriptions.retrieve(session.subscription);
    if(session.metadata?.supabase_user_id && !sub.metadata?.supabase_user_id){sub=await stripe.subscriptions.update(sub.id,{metadata:{supabase_user_id:session.metadata.supabase_user_id}});}
    await setPlan(sub,stripe);
   }
  } else if(event.type==="invoice.payment_failed"){
   const invoice=event.data.object as Stripe.Invoice;
   const invoiceWithParent=invoice as Stripe.Invoice & {parent?: {type?: string; subscription_details?: {subscription?: string | {id:string} | null} | null} | null};
   const subscription=invoiceWithParent.parent?.type==="subscription_details" ? invoiceWithParent.parent.subscription_details?.subscription : null;
   const subId=typeof subscription==="string"?subscription:subscription?.id??null;
   if(subId){const sub=await stripe.subscriptions.retrieve(subId);await setPlan(sub,stripe);}
  } else if(event.type==="invoice.paid"){
   const invoice=event.data.object as Stripe.Invoice;
   const invoiceWithParent=invoice as Stripe.Invoice & {parent?: {type?: string; subscription_details?: {subscription?: string | {id:string} | null} | null} | null};
   const subscription=invoiceWithParent.parent?.type==="subscription_details" ? invoiceWithParent.parent.subscription_details?.subscription : null;
   const subId=typeof subscription==="string"?subscription:subscription?.id??null;
   if(subId){const sub=await stripe.subscriptions.retrieve(subId);await setPlan(sub,stripe);}
  }
  return NextResponse.json({received:true});
 }catch(e){console.error("Stripe webhook processing failed",e);try{await admin.from("stripe_events").delete().eq("event_id",event.id);}catch{}return NextResponse.json({error:"Webhook processing failed"},{status:500});}
     }
