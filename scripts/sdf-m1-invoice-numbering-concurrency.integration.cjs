const { spawn, spawnSync } = require("node:child_process");

const container = process.env.SUPABASE_DB_CONTAINER || "supabase_db_xcsptvntvrizwhskaphr";
const psqlArgs = ["exec", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c"];
const issueYear = 2198;
const nextIssueYear = 2199;
const requestCount = 12;

function query(sql) {
  const result = spawnSync("docker", [...psqlArgs, sql], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout.trim();
}

function run(sql) {
  return new Promise((resolve) => {
    const child = spawn("docker", [...psqlArgs, sql]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (data) => stdout += data);
    child.stderr.on("data", (data) => stderr += data);
    child.on("exit", (code) => resolve({ code, stdout: stdout.trim(), stderr: stderr.trim() }));
  });
}

query(`delete from public.sdf_invoice_number_counters where issue_year in (${issueYear},${nextIssueYear});`);
const websiteCounterBefore = query("select coalesce(jsonb_agg(to_jsonb(counter) order by year)::text,'[]') from public.quotation_number_counters as counter;");

Promise.all(Array.from({ length: requestCount }, () => run(
  `select invoice_number || '|' || sequence from public.allocate_sdf_invoice_number_v1(${issueYear}::smallint);`
))).then((results) => {
  const failures = results.filter((result) => result.code !== 0);
  if (failures.length) throw new Error(`CONCURRENT_ALLOCATION_FAILURE:${JSON.stringify(failures)}`);

  const outcomes = results.map((result) => result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1));
  const numbers = outcomes.map((outcome) => outcome.split("|")[0]);
  const sequences = outcomes.map((outcome) => Number(outcome.split("|")[1])).sort((left, right) => left - right);
  if (new Set(numbers).size !== requestCount) {
    throw new Error(`CONCURRENT_NUMBER_DUPLICATE:${JSON.stringify(outcomes)}`);
  }
  if (numbers.some((number) => !new RegExp(`^LWS-${issueYear}-[0-9]{4}$`).test(number))) {
    throw new Error(`CONCURRENT_NUMBER_FORMAT_INVALID:${JSON.stringify(outcomes)}`);
  }
  if (sequences.join(",") !== Array.from({ length: requestCount }, (_, index) => index + 1).join(",")) {
    throw new Error(`CONCURRENT_SEQUENCE_GAP:${JSON.stringify(sequences)}`);
  }

  const nextYear = query(`select invoice_number || '|' || sequence from public.allocate_sdf_invoice_number_v1(${nextIssueYear}::smallint);`);
  if (nextYear !== `LWS-${nextIssueYear}-0001|1`) {
    throw new Error(`ANNUAL_RESET_INVALID:${nextYear}`);
  }

  const websiteCounterAfter = query("select coalesce(jsonb_agg(to_jsonb(counter) order by year)::text,'[]') from public.quotation_number_counters as counter;");
  if (websiteCounterAfter !== websiteCounterBefore) {
    throw new Error("WEBSITE_QUOTATION_COUNTER_CHANGED");
  }

  query(`delete from public.sdf_invoice_number_counters where issue_year in (${issueYear},${nextIssueYear});`);
  process.stdout.write(JSON.stringify({
    test_context: "LOCAL_TEST_ONLY",
    concurrent_allocations: requestCount,
    unique_numbers: new Set(numbers).size,
    minimum_sequence: sequences[0],
    maximum_sequence: sequences.at(-1),
    annual_reset: nextYear,
    website_quotation_counter_unchanged: true,
  }) + "\n");
}).catch((error) => {
  try {
    query(`delete from public.sdf_invoice_number_counters where issue_year in (${issueYear},${nextIssueYear});`);
  } catch {}
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
