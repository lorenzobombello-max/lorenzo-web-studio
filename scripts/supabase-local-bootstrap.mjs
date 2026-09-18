import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import {
  access,
  cp,
  mkdtemp,
  readFile,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const EXPECTED_PROJECT_ID = 'xcsptvntvrizwhskaphr';
export const TARGET_MIGRATION = '20260903190000_bind_operator_profiles_to_auth_users_v1.sql';
export const FIXTURE_BEGIN = '-- LOCAL_BOOTSTRAP_FIXTURE_BEGIN';
export const FIXTURE_END = '-- LOCAL_BOOTSTRAP_FIXTURE_END';

const UUID_PATTERN = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const FORBIDDEN_ARGUMENTS = ['--linked', '--db-url', '--project-ref'];
const TARGET_ENVIRONMENT_KEYS = /^(?:DATABASE_URL|POSTGRES_URL(?:_NON_POOLING)?|SUPABASE_(?:DB_)?URL)$/i;
const LOOPBACK_HOSTS = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);

function normalizeIdentities(identities) {
  return identities.map(({ id, email }) => ({ id: id.toLowerCase(), email: email.toLowerCase() }));
}

function assertThreeUniqueIdentities(identities, sourceName) {
  if (identities.length !== 3) {
    throw new Error(`${sourceName} must define exactly three Auth identities`);
  }
  if (new Set(identities.map(({ id }) => id)).size !== 3 || new Set(identities.map(({ email }) => email)).size !== 3) {
    throw new Error(`${sourceName} contains duplicate Auth authority`);
  }
}

export function extractMigrationAuthority(migrationSql) {
  const pattern = new RegExp(
    `where\\s+id\\s*=\\s*'(${UUID_PATTERN})'\\s+and\\s+email\\s*=\\s*'([^']+)'\\s+and\\s+email_confirmed_at\\s+is\\s+not\\s+null`,
    'gi',
  );
  const identities = normalizeIdentities(
    [...migrationSql.matchAll(pattern)].map((match) => ({ id: match[1], email: match[2] })),
  );
  assertThreeUniqueIdentities(identities, 'Binding migration');
  return { identities, emailConfirmedRequired: true };
}

export function extractFixtureAuthority(fixtureSql) {
  const pattern = new RegExp(`\\('(${UUID_PATTERN})'::uuid,\\s*'([^']+)'::text\\)`, 'gi');
  const identities = normalizeIdentities(
    [...fixtureSql.matchAll(pattern)].map((match) => ({ id: match[1], email: match[2] })),
  );
  assertThreeUniqueIdentities(identities, 'Local fixture');
  if (!/email_confirmed_at/i.test(fixtureSql)) {
    throw new Error('Local fixture must populate email confirmation state');
  }
  return identities;
}

export function assertFixtureContainsNoCredentials(fixtureSql) {
  if (/password|token|service[_-]?role|secret|credential|refresh|encrypted_password/i.test(fixtureSql)) {
    throw new Error('Local fixture contains forbidden credential material');
  }
}

export function assertAuthorityMatch(migrationAuthority, fixtureAuthority) {
  if (!migrationAuthority.emailConfirmedRequired) {
    throw new Error('Binding migration confirmation invariant was not found');
  }
  if (JSON.stringify(migrationAuthority.identities) !== JSON.stringify(fixtureAuthority)) {
    throw new Error('Fixture authority does not match the binding migration');
  }
}

export function validateCliArguments(args) {
  for (const argument of args) {
    const normalized = argument.toLowerCase();
    if (FORBIDDEN_ARGUMENTS.some((forbidden) => normalized === forbidden || normalized.startsWith(`${forbidden}=`))) {
      throw new Error(`Forbidden remote targeting argument: ${argument}`);
    }
    assertLocalTargetValue(argument);
  }
  if (args.length > 1 || (args.length === 1 && args[0] !== '--dry-run')) {
    throw new Error('Unsupported argument; only --dry-run is accepted');
  }
  return { dryRun: args[0] === '--dry-run' };
}

export function assertLocalTargetValue(value) {
  if (typeof value !== 'string') {
    return;
  }
  const normalized = value.toLowerCase();
  if (normalized.includes('.supabase.co') || normalized.includes('pooler.supabase.com')) {
    throw new Error('Remote Supabase targets are forbidden');
  }
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) {
    return;
  }
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error('Malformed target URL is forbidden');
  }
  if (!LOOPBACK_HOSTS.has(parsed.hostname.toLowerCase())) {
    throw new Error(`Only loopback targets are permitted: ${parsed.hostname}`);
  }
}

export function assertLocalEnvironment(environment = process.env) {
  for (const [key, value] of Object.entries(environment)) {
    if (TARGET_ENVIRONMENT_KEYS.test(key) && value) {
      assertLocalTargetValue(value);
    }
  }
}

export function extractProjectId(configToml) {
  const match = configToml.match(/^project_id\s*=\s*"([^"]+)"\s*$/m);
  if (!match) {
    throw new Error('Supabase config has no project_id');
  }
  return match[1];
}

export function assertExpectedProject(projectId) {
  if (projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(`Unexpected Supabase project: ${projectId}`);
  }
}

export function assertConfigLocalOnly(configToml) {
  for (const match of configToml.matchAll(/(?:postgres(?:ql)?|https?):\/\/[^\s"']+/gi)) {
    assertLocalTargetValue(match[0]);
  }
  if (/\.supabase\.co|pooler\.supabase\.com/i.test(configToml)) {
    throw new Error('Supabase config contains a remote target');
  }
}

export function shouldCopySupabasePath(relativePath) {
  const segments = relativePath.replaceAll('\\', '/').split('/').filter(Boolean);
  return !segments.includes('.temp') && !segments.includes('.branches');
}

export function injectFixture(migrationSql, fixtureSql) {
  if (migrationSql.includes(FIXTURE_BEGIN) || migrationSql.includes(FIXTURE_END)) {
    throw new Error('Local bootstrap fixture marker already exists');
  }
  const anchor = migrationSql.search(/^do \$\$/m);
  if (anchor < 0) {
    throw new Error('Binding migration invariant block was not found');
  }
  const newline = migrationSql.includes('\r\n') ? '\r\n' : '\n';
  const fixtureBlock = [FIXTURE_BEGIN, fixtureSql.trim(), FIXTURE_END, ''].join(newline);
  return `${migrationSql.slice(0, anchor)}${fixtureBlock}${migrationSql.slice(anchor)}`;
}

export async function pathExists(targetPath) {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}

export async function withTemporaryWorkdir(operation) {
  const tempPath = await mkdtemp(path.join(os.tmpdir(), 'lws-supabase-bootstrap-'));
  try {
    return await operation(tempPath);
  } finally {
    await rm(tempPath, { recursive: true, force: true });
  }
}

async function sha256(filePath) {
  return createHash('sha256').update(await readFile(filePath)).digest('hex');
}

function runProcess(file, args, options) {
  return new Promise((resolve, reject) => {
    const child = spawn(file, args, { ...options, shell: false });
    child.once('error', reject);
    child.once('exit', (code, signal) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${path.basename(file)} exited with ${code ?? signal}`));
      }
    });
  });
}

async function assertGitRepository(repositoryRoot) {
  const gitMetadata = path.join(repositoryRoot, '.git');
  const metadata = await stat(gitMetadata).catch(() => null);
  if (!metadata) {
    throw new Error('Source directory is not a Git repository');
  }
  await runProcess('git', ['rev-parse', '--is-inside-work-tree'], {
    cwd: repositoryRoot,
    stdio: 'ignore',
  });
}

export async function createBootstrapPlan({ repositoryRoot }) {
  await assertGitRepository(repositoryRoot);
  const configPath = path.join(repositoryRoot, 'supabase', 'config.toml');
  const migrationPath = path.join(repositoryRoot, 'supabase', 'migrations', TARGET_MIGRATION);
  const fixturePath = path.join(repositoryRoot, 'supabase', 'local-bootstrap', 'operator-auth-identities.sql');
  const [configToml, migrationSql, fixtureSql] = await Promise.all([
    readFile(configPath, 'utf8'),
    readFile(migrationPath, 'utf8'),
    readFile(fixturePath, 'utf8'),
  ]);
  assertExpectedProject(extractProjectId(configToml));
  assertConfigLocalOnly(configToml);
  assertFixtureContainsNoCredentials(fixtureSql);
  const authority = extractMigrationAuthority(migrationSql);
  const fixtureAuthority = extractFixtureAuthority(fixtureSql);
  assertAuthorityMatch(authority, fixtureAuthority);
  return {
    authority,
    configPath,
    fixturePath,
    migrationPath,
    sourceHashes: {
      config: await sha256(configPath),
      fixture: await sha256(fixturePath),
      migration: await sha256(migrationPath),
    },
    injectedMigrationSql: injectFixture(migrationSql, fixtureSql),
  };
}

async function copySupabaseProject(repositoryRoot, tempRoot) {
  const source = path.join(repositoryRoot, 'supabase');
  const destination = path.join(tempRoot, 'supabase');
  await cp(source, destination, {
    recursive: true,
    filter: (sourcePath) => shouldCopySupabasePath(path.relative(source, sourcePath)),
  });
}

function replaceTomlValue(configToml, section, key, value) {
  const sectionPattern = new RegExp(`(\\[${section.replaceAll('.', '\\.')}\\][\\s\\S]*?)(?=\\n\\[|$)`);
  const sectionMatch = configToml.match(sectionPattern);
  const rendered = typeof value === 'number' ? String(value) : `"${value}"`;
  if (!sectionMatch) {
    return `${configToml.trimEnd()}\n\n[${section}]\n${key} = ${rendered}\n`;
  }
  const keyPattern = new RegExp(`^${key}\\s*=.*$`, 'm');
  const updatedSection = keyPattern.test(sectionMatch[1])
    ? sectionMatch[1].replace(keyPattern, `${key} = ${rendered}`)
    : `${sectionMatch[1].trimEnd()}\n${key} = ${rendered}\n`;
  return configToml.replace(sectionPattern, updatedSection);
}

async function applyRuntimeOverrides(tempRoot, runtimeProjectId, runtimePorts = {}) {
  if (!runtimeProjectId && Object.keys(runtimePorts).length === 0) {
    return;
  }
  if (runtimeProjectId && !/^[a-z0-9_-]+$/.test(runtimeProjectId)) {
    throw new Error('Invalid synthetic local project identifier');
  }
  const configPath = path.join(tempRoot, 'supabase', 'config.toml');
  let configToml = await readFile(configPath, 'utf8');
  if (runtimeProjectId) {
    configToml = configToml.replace(/^project_id\s*=.*$/m, `project_id = "${runtimeProjectId}"`);
  }
  for (const [qualifiedKey, value] of Object.entries(runtimePorts)) {
    if (!Number.isInteger(value) || value < 1024 || value > 65535 || !qualifiedKey.includes('.')) {
      throw new Error(`Invalid synthetic local port override: ${qualifiedKey}`);
    }
    const separator = qualifiedKey.lastIndexOf('.');
    configToml = replaceTomlValue(configToml, qualifiedKey.slice(0, separator), qualifiedKey.slice(separator + 1), value);
  }
  await writeFile(configPath, configToml, 'utf8');
}

export function buildSupabaseCommand(tempRoot, lifecycleArgs = ['start'], executable) {
  const allowedLifecycle = JSON.stringify(lifecycleArgs) === JSON.stringify(['start']);
  if (!allowedLifecycle) {
    throw new Error('Unsupported Supabase lifecycle command');
  }
  const file = typeof executable === 'object'
    ? executable.file
    : executable ?? (process.platform === 'win32' ? 'npx.cmd' : 'npx');
  const prefix = typeof executable === 'object'
    ? executable.prefix
    : executable ? [] : ['--no-install', 'supabase'];
  if (!file || !Array.isArray(prefix) || prefix.some((argument) => typeof argument !== 'string')) {
    throw new Error('Invalid internal Supabase executable adapter');
  }
  return {
    file,
    args: [...prefix, '--workdir', tempRoot, ...lifecycleArgs],
    options: { shell: false },
  };
}

async function assertSourceHashes(plan) {
  const current = {
    config: await sha256(plan.configPath),
    fixture: await sha256(plan.fixturePath),
    migration: await sha256(plan.migrationPath),
  };
  if (JSON.stringify(current) !== JSON.stringify(plan.sourceHashes)) {
    throw new Error('Source repository changed during local bootstrap');
  }
}

export async function bootstrapLocalSupabase({
  repositoryRoot,
  dryRun = false,
  runtimeProjectId,
  runtimePorts,
  supabaseExecutable,
} = {}) {
  assertLocalEnvironment();
  const plan = await createBootstrapPlan({ repositoryRoot });
  try {
    return await withTemporaryWorkdir(async (tempRoot) => {
      await copySupabaseProject(repositoryRoot, tempRoot);
      await applyRuntimeOverrides(tempRoot, runtimeProjectId, runtimePorts);
      const temporaryMigration = path.join(tempRoot, 'supabase', 'migrations', TARGET_MIGRATION);
      await writeFile(temporaryMigration, plan.injectedMigrationSql, 'utf8');
      if (!dryRun) {
        const command = buildSupabaseCommand(tempRoot, ['start'], supabaseExecutable);
        await runProcess(command.file, command.args, {
          ...command.options,
          cwd: repositoryRoot,
          env: process.env,
          stdio: 'inherit',
        });
      }
      return { authority: plan.authority, dryRun };
    });
  } finally {
    await assertSourceHashes(plan);
  }
}

async function main() {
  const { dryRun } = validateCliArguments(process.argv.slice(2));
  const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const result = await bootstrapLocalSupabase({ repositoryRoot, dryRun });
  process.stdout.write(`Local Supabase bootstrap ${result.dryRun ? 'validated' : 'completed'}.\n`);
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}