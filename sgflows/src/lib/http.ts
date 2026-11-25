import { NextResponse } from "next/server";
export function jsonError(message:string,status=400){return NextResponse.json({error:message},{status})}
export function isDemo(){return process.env.SIGNALFLOW_DEMO_MODE==="true"&&process.env.NODE_ENV!=="production"}
