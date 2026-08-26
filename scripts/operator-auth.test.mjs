import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  buildEmailOtpRequest,
  buildEmailOtpVerification,
  buildMagicLinkRequest,
  callCommercialOperator,
  classifyAuthError,
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
import { createOperatorLoginController } from "../assets/js/operator-login.mjs";

const validConfig={supabaseUrl:"https://xcsptvntvrizwhskaphr.supabase.co",publishableKey:"sb_publishable_test_public",callbackUrl:"https://lorenzowebsolutions.be/operator/auth/callback/"};
const session={access_token:"token-never-logged",expires_at:4102444800,user:{id:"993a4b95-0d63-48e7-9733-0bda6422b50f",email:"bombello.lorenzo1972@gmail.com"}};
const loginHtml=readFileSync(new URL("../operator/login/index.html",import.meta.url),"utf8");

function createLoginHarness(authOverrides={},options={}) {
  const element=(value="")=>({value,hidden:false,disabled:false,textContent:"",dataset:{},focus(){this.focused=true}});
  const elements={emailForm:element(),codeForm:element(),emailInput:element(" Owner@Example.COM "),codeInput:element(),emailSubmit:element(),verifySubmit:element(),resendButton:element(),resendStatus:element(),differentEmailButton:element(),message:element()};
  elements.codeForm.hidden=true;
  let destination=null;
  let now=1_000_000;
  const auth={signInWithOtp:async()=>({error:null}),verifyOtp:async()=>({data:{session},error:null}),...authOverrides};
  const controller=createOperatorLoginController({client:{auth},elements,navigate:(path)=>destination=path,now:()=>now,setTimer:()=>1,clearTimer:()=>{},...options});
  return{auth,controller,elements,get destination(){return destination},advance:(seconds)=>now+=seconds*1000};
}

test("public config is exact and frozen",()=>assert.equal(validatePublicConfig(validConfig).callbackUrl,validConfig.callbackUrl));
test("service-role-like browser config is rejected",()=>assert.throws(()=>validatePublicConfig({...validConfig,publishableKey:"service_role"}),/AUTH_CONFIG_INVALID/));
test("magic-link login cannot create users",()=>assert.equal(buildMagicLinkRequest(" Owner@Example.COM ",validConfig.callbackUrl).options.shouldCreateUser,false));
test("magic-link callback is exact",()=>assert.equal(buildMagicLinkRequest("owner@example.com",validConfig.callbackUrl).options.emailRedirectTo,validConfig.callbackUrl));
test("email OTP request cannot create users and has no redirect",()=>assert.deepEqual(buildEmailOtpRequest(" Owner@Example.COM "),{email:"owner@example.com",options:{shouldCreateUser:false}}));
test("email state is visible and code state starts hidden",()=>{assert.match(loginHtml,/data-operator-email-step/);assert.match(loginHtml,/data-operator-code-step[^>]*hidden/)});
test("successful send opens the code state",async()=>{const harness=createLoginHarness();assert.equal(await harness.controller.requestCode(),true);assert.equal(harness.elements.emailForm.hidden,true);assert.equal(harness.elements.codeForm.hidden,false)});
test("OTP verification contract is exact",()=>assert.deepEqual(buildEmailOtpVerification(" Owner@Example.COM "," 123456 "),{email:"owner@example.com",token:"123456",type:"email"}));
test("OTP accepts exactly six numeric characters",()=>{assert.throws(()=>buildEmailOtpVerification("owner@example.com","12345"),/OTP_FORMAT_INVALID/);assert.throws(()=>buildEmailOtpVerification("owner@example.com","1234567"),/OTP_FORMAT_INVALID/);assert.throws(()=>buildEmailOtpVerification("owner@example.com","12345a"),/OTP_FORMAT_INVALID/)});
test("invalid frontend OTP never reaches Supabase",async()=>{let calls=0;const harness=createLoginHarness({verifyOtp:async()=>{calls++;return{data:{session},error:null}}});harness.elements.codeInput.value="12ab56";assert.equal(await harness.controller.verifyCode(),false);assert.equal(calls,0)});
test("successful verification navigates to operator home",async()=>{let request;const harness=createLoginHarness({verifyOtp:async(value)=>(request=value,{data:{session},error:null})});await harness.controller.requestCode();harness.elements.codeInput.value="123456";assert.equal(await harness.controller.verifyCode(),true);assert.deepEqual(request,{email:"owner@example.com",token:"123456",type:"email"});assert.equal(harness.destination,OPERATOR_ROUTES.home)});
test("invalid and expired OTP errors are mapped safely",()=>{assert.equal(classifyAuthError({status:403,code:"invalid_otp",message:"raw"}).safeCode,"OTP_INVALID");assert.equal(classifyAuthError({status:403,code:"otp_expired",message:"raw"}).safeCode,"OTP_EXPIRED")});
test("429 keeps status and code while selecting a safe message",()=>{const result=classifyAuthError({status:429,code:"over_email_send_rate_limit",message:"raw backend detail",retryAfter:75});assert.deepEqual({status:result.status,code:result.code,safeCode:result.safeCode,retryAfterSeconds:result.retryAfterSeconds},{status:429,code:"over_email_send_rate_limit",safeCode:"AUTH_RATE_LIMITED",retryAfterSeconds:75})});
test("network failures have a safe category",()=>assert.equal(classifyAuthError(new TypeError("Failed to fetch")).safeCode,"AUTH_NETWORK_ERROR"));
test("parallel send requests are blocked",async()=>{let resolve;let calls=0;const pending=new Promise((done)=>resolve=done);const harness=createLoginHarness({signInWithOtp:async()=>{calls++;await pending;return{error:null}}});const first=harness.controller.requestCode();const second=harness.controller.requestCode();assert.equal(await second,false);assert.equal(calls,1);resolve();await first});
test("parallel verification requests are blocked",async()=>{let resolve;let calls=0;const pending=new Promise((done)=>resolve=done);const harness=createLoginHarness({verifyOtp:async()=>{calls++;await pending;return{data:{session},error:null}}});await harness.controller.requestCode();harness.elements.codeInput.value="123456";const first=harness.controller.verifyCode();const second=harness.controller.verifyCode();assert.equal(await second,false);assert.equal(calls,1);resolve();await first});
test("resend is blocked during local cooldown",async()=>{let calls=0;const harness=createLoginHarness({signInWithOtp:async()=>(calls++,{error:null})});await harness.controller.requestCode();assert.equal(await harness.controller.resendCode(),false);assert.equal(calls,1);assert.equal(harness.elements.resendButton.disabled,true)});
test("429 response shows safe cooldown UI without raw backend text",async()=>{const harness=createLoginHarness({signInWithOtp:async()=>({error:{status:429,code:"over_email_send_rate_limit",message:"raw backend detail",retryAfter:75}})});assert.equal(await harness.controller.requestCode(),false);assert.equal(harness.controller.getState().lastError.status,429);assert.equal(harness.controller.getState().cooldownRemaining,75);assert.match(harness.elements.message.textContent,/te veel aanmeldcodes/);assert.doesNotMatch(harness.elements.message.textContent,/raw backend detail/)});
test("thrown SDK network failure is mapped safely",async()=>{const harness=createLoginHarness({signInWithOtp:async()=>{throw new TypeError("Failed to fetch")}});assert.equal(await harness.controller.requestCode(),false);assert.equal(harness.controller.getState().lastError.safeCode,"AUTH_NETWORK_ERROR");assert.match(harness.elements.message.textContent,/niet bereikbaar/)});
test("different email resets transient OTP state",async()=>{const harness=createLoginHarness();await harness.controller.requestCode();harness.elements.codeInput.value="123456";harness.controller.useDifferentEmail();assert.equal(harness.elements.emailForm.hidden,false);assert.equal(harness.elements.codeForm.hidden,true);assert.equal(harness.elements.codeInput.value,"");assert.equal(harness.controller.getState().retainedEmail,"")});
test("login flow does not persist email or OTP",()=>{const source=readFileSync(new URL("../assets/js/operator-login.mjs",import.meta.url),"utf8");assert.doesNotMatch(source,/localStorage|sessionStorage/)});
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
