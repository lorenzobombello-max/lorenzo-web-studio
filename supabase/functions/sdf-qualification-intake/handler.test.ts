import { assertEquals } from "jsr:@std/assert@1";
import { handleSdfQualificationIntake, SDF_CONFIRMATION_VERSION } from "./handler.ts";

const token="a".repeat(43);
function request(body: Record<string,unknown>,authorization=`Bearer ${token}`) { return new Request("https://example.test/sdf-qualification-intake",{method:"POST",headers:{"content-type":"application/json","authorization":authorization},body:JSON.stringify(body)}); }
const hashCapability=async()=>"b".repeat(64);

Deno.test("SDF intake rejects missing capability before RPC dispatch",async()=>{
  let calls=0; const response=await handleSdfQualificationIntake(request({action:"inspect"},""),{hashCapability,rpc:async()=>{calls+=1;return{data:null,error:null};}});
  assertEquals(response.status,401); assertEquals(calls,0);
});

Deno.test("SDF intake inspect returns server-owned confirmation authority",async()=>{
  const names:string[]=[]; const response=await handleSdfQualificationIntake(request({action:"inspect"}),{hashCapability,rpc:async(name)=>{names.push(name);return name.startsWith("consume_")?{data:true,error:null}:{data:{status:"invited",draft_revision:0},error:null};}});
  const output=await response.json(); assertEquals(response.status,200); assertEquals(names,["consume_sdf_qualification_rate_limit_v1","inspect_sdf_qualification_intake_v1"]); assertEquals(output.confirmation.version,SDF_CONFIRMATION_VERSION); assertEquals(output.confirmation.sha256.length,64);
});

Deno.test("SDF intake submit supplies fixed confirmation integrity and idempotency",async()=>{
  let parameters:Record<string,unknown>={}; const response=await handleSdfQualificationIntake(request({action:"submit",expected_revision:2,idempotency_key:"11111111-1111-4111-8111-111111111111",confirmation_accepted:true,confirmation_version:SDF_CONFIRMATION_VERSION}),{hashCapability,rpc:async(name,input)=>{if(name.startsWith("consume_"))return{data:true,error:null};parameters=input;return{data:{status:"submitted"},error:null};}});
  assertEquals(response.status,200); assertEquals(parameters.p_confirmation_accepted,true); assertEquals(parameters.p_confirmation_version,SDF_CONFIRMATION_VERSION); assertEquals(String(parameters.p_confirmation_sha256).length,64); assertEquals(parameters.p_expected_revision,2);
});

Deno.test("SDF intake submit rejects absent, unchecked, wrong-version, and client hash confirmation",async()=>{
  for(const invalid of [
    {action:"submit",expected_revision:2,idempotency_key:"11111111-1111-4111-8111-111111111111"},
    {action:"submit",expected_revision:2,idempotency_key:"11111111-1111-4111-8111-111111111111",confirmation_accepted:false,confirmation_version:SDF_CONFIRMATION_VERSION},
    {action:"submit",expected_revision:2,idempotency_key:"11111111-1111-4111-8111-111111111111",confirmation_accepted:true,confirmation_version:"wrong"},
    {action:"submit",expected_revision:2,idempotency_key:"11111111-1111-4111-8111-111111111111",confirmation_accepted:true,confirmation_version:SDF_CONFIRMATION_VERSION,confirmation_sha256:"a".repeat(64)},
  ]){
    let submitted=false;
    const response=await handleSdfQualificationIntake(request(invalid),{hashCapability,rpc:async(name)=>{if(name.startsWith("consume_"))return{data:true,error:null};submitted=true;return{data:null,error:null};}});
    assertEquals(response.status,400); assertEquals(submitted,false);
  }
});

Deno.test("SDF browser payload preserves C4A and adds only V2 commercial qualification inputs",async()=>{
  const source=await Deno.readTextFile(new URL("../../../assets/js/sdf-qualification-intake.js",import.meta.url));
  for(const field of ["documentPurpose","workflowCapabilities","businessRequirements","currentWorkflow","desiredWorkflow","volumeBand","frequency","relevantDocumentTypes","rolesUsers","sampleDocumentMetadata","available","requestedByLws","uploadRequiredLater","commercialQualification","packageDirection","customComplexity","documentVolumes","documentType","documentCount","period","averagePagesPerDocument"]){
    assertEquals(source.includes(field),true);
  }
  for(const prohibited of ["sampleNotes","priceMinor","estimatedPagesPerPeriod","totalDocuments","totalPages"]){
    assertEquals(source.includes(prohibited),false);
  }
});