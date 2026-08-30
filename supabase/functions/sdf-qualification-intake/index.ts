import { createClient } from "npm:@supabase/supabase-js@2";
import { hashIntakeToken } from "../_shared/security.ts";
import { handleSdfQualificationIntake } from "./handler.ts";

const url=Deno.env.get("SUPABASE_URL")||"";
const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});

Deno.serve((request)=>url&&key
  ? handleSdfQualificationIntake(request,{hashCapability:hashIntakeToken,rpc:async(name,parameters)=>await client.rpc(name,parameters)})
  : new Response(JSON.stringify({ok:false,code:"SERVER_CONFIGURATION_ERROR"}),{status:500,headers:{"content-type":"application/json","cache-control":"no-store"}}));