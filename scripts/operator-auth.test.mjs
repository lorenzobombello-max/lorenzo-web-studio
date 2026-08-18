import assert from "node:assert/strict";
import test from "node:test";
import {
  buildMagicLinkRequest,
  callCommercialOperator,
  hasAuthCallbackMaterial,
  isUsableSession,
  OPERATOR_ROUTES,
  requireAuthorizedOperator,
  requireOperatorSession,
  resolveAuthCallback,
  scrubAuthUrl,
  signOutOperator,
  validatePublicConfig,
} from "../assets/js/operator-auth-core.mjs";

const validConfig={supabaseUrl:"https://xcsptvntvrizwhskaphr.supabase.co",publishableKey:"sb_publishable_test_public",callbackUrl:"https://lorenzowebsolutions.be/operator/auth/callback/"};
const session={access_token:"token-never-logged",expires_at:4102444800,user:{id:"993a4b95-0d63-48e7-9733-0bda6422b50f",email:"bombello.lorenzo1972@gmail.com"}};

test("public config is exact and frozen",()=>assert.equal(validatePublicConfig(validConfig).callbackUrl,validConfig.callbackUrl));
test("service-role-like browser config is rejected",()=>assert.throws(()=>validatePublicConfig({...validConfig,publishableKey:"service_role"}),/AUTH_CONFIG_INVALID/));
test("magic-link login cannot create users",()=>assert.equal(buildMagicLinkRequest(" Owner@Example.COM ",validConfig.callbackUrl).options.shouldCreateUser,false));
test("magic-link callback is exact",()=>assert.equal(buildMagicLinkRequest("owner@example.com",validConfig.callbackUrl).options.emailRedirectTo,validConfig.callbackUrl));
test("callback material detects PKCE code",()=>assert.equal(hasAuthCallbackMaterial("https://lorenzowebsolutions.be/operator/auth/callback/?code=x"),true));
test("callback material detects invitation fragment",()=>assert.equal(hasAuthCallbackMaterial("https://lorenzowebsolutions.be/operator/auth/callback/#access_token=x&refresh_token=y"),true));
test("ordinary operator URL has no callback material",()=>assert.equal(hasAuthCallbackMaterial("https://lorenzowebsolutions.be/operator/"),false));
test("URL cleanup removes query and fragment",()=>{let replaced;const path=scrubAuthUrl({pathname:OPERATOR_ROUTES.callback},{state:null,replaceState:(_s,_t,url)=>replaced=url});assert.equal(path,OPERATOR_ROUTES.callback);assert.equal(replaced,OPERATOR_ROUTES.callback)});
test("valid session is usable",()=>assert.equal(isUsableSession(session,1700000000),true));
test("expired session is denied",()=>assert.equal(isUsableSession({...session,expires_at:1},1700000000),false));
test("callback establishes session and always cleans URL",async()=>{let replaced;const result=await resolveAuthCallback({auth:{getSession:async()=>({data:{session},error:null})}},{location:{href:"https://lorenzowebsolutions.be/operator/auth/callback/?code=x",pathname:OPERATOR_ROUTES.callback},history:{state:null,replaceState:(_s,_t,url)=>replaced=url},nowSeconds:()=>1700000000});assert.equal(result.ok,true);assert.equal(replaced,OPERATOR_ROUTES.callback)});
test("callback without auth result fails safely",async()=>{const result=await resolveAuthCallback({auth:{getSession:async()=>({data:{session:null},error:null})}},{location:{href:"https://lorenzowebsolutions.be/operator/auth/callback/",pathname:OPERATOR_ROUTES.callback},history:{replaceState(){}},nowSeconds:()=>1700000000});assert.equal(result.code,"SESSION_NOT_AVAILABLE")});
test("protected route restores valid SDK session",async()=>assert.equal((await requireOperatorSession({auth:{getSession:async()=>({data:{session},error:null})}},1700000000)).user.id,session.user.id));
test("protected route rejects missing session",async()=>assert.equal(await requireOperatorSession({auth:{getSession:async()=>({data:{session:null},error:null})}},1700000000),null));
test("dashboard route is canonical",()=>assert.equal(OPERATOR_ROUTES.dashboard,"/operator/dashboard/"));
test("active operator passes the read-only database authority probe",async()=>assert.equal((await requireAuthorizedOperator({auth:{getSession:async()=>({data:{session},error:null})},rpc:async()=>({data:null,error:{code:"23503",message:"PROJECT_NOT_FOUND"}})},1700000000)).status,"authorized"));
test("non-operator session is denied by the database authority probe",async()=>assert.equal((await requireAuthorizedOperator({auth:{getSession:async()=>({data:{session},error:null})},rpc:async()=>({data:null,error:{code:"42501",message:"UNKNOWN_OPERATOR"}})},1700000000)).status,"unauthorized"));
test("logged-out dashboard request does not call the authority RPC",async()=>{let called=false;const result=await requireAuthorizedOperator({auth:{getSession:async()=>({data:{session:null},error:null})},rpc:async()=>{called=true;return{data:null,error:null}}},1700000000);assert.equal(result.status,"unauthenticated");assert.equal(called,false)});
test("logout uses SDK local scope",async()=>{let scope;await signOutOperator({auth:{signOut:async(options)=>(scope=options.scope,{error:null})}});assert.equal(scope,"local")});
test("Edge request uses current session bearer only",async()=>{let headers;await callCommercialOperator({auth:{getSession:async()=>({data:{session},error:null})}},"https://xcsptvntvrizwhskaphr.supabase.co/functions/v1",{command_type:"archive_project"},async(_url,options)=>(headers=options.headers,{status:409,json:async()=>({code:"COMMAND_REJECTED"})}));assert.equal(headers.Authorization,`Bearer ${session.access_token}`)});
