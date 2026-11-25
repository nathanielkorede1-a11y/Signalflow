import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
export async function GET(){const sb=await createClient();const {data:{user}}=await sb.auth.getUser();if(!user)return NextResponse.json({error:"Authentication required"},{status:401});return NextResponse.json({id:user.id,email:user.email??null});}
