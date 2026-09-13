import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  type RepositoryBinding,
  repositoryNameForContext,
  type RepositoryProvisioningClaim,
  type RepositoryProvisioningCommand,
  type RepositoryProvisioningCommandV2,
  type RepositoryProvisioningProvider,
  type RepositoryProvisioningProviderV2,
  RepositoryProvisioningService,
  RepositoryProvisioningServiceV2,
  type RepositoryProvisioningStore,
  type RepositoryProvisioningStoreV2,
  type VerifiedRepositoryBindingV2,
} from "./repository-provisioning.ts";

const command: RepositoryProvisioningCommand = Object.freeze({
  websiteWorkspaceId: "d1110000-0000-4000-8000-000000000001",
  websiteWorkContextId: "d1120000-0000-4000-8000-000000000001",
  idempotencyKey: "d1130000-0000-4000-8000-000000000001",
  repositoryName: "lws-web-dossier-0042",
});

const repository: RepositoryBinding = Object.freeze({
  provider: "GITHUB",
  providerRepositoryId: "982451653",
  owner: "lws-studio",
  name: command.repositoryName,
  visibility: "PRIVATE",
  defaultBranch: "main",
});

function harness(claim: RepositoryProvisioningClaim = {
  state: "CLAIMED",
  operationId: "d1140000-0000-4000-8000-000000000001",
}) {
  const providerCalls: unknown[] = [];
  const bindCalls: unknown[] = [];
  const failCalls: unknown[] = [];
  const provider: RepositoryProvisioningProvider = {
    provision: (request) => {
      providerCalls.push(request);
      return Promise.resolve(repository);
    },
  };
  const store: RepositoryProvisioningStore = {
    claim: () => Promise.resolve(claim),
    bind: (operationId, expected, binding) => {
      bindCalls.push({ operationId, expected, binding });
      return Promise.resolve(binding);
    },
    fail: (operationId, code) => {
      failCalls.push({ operationId, code });
      return Promise.resolve();
    },
  };
  return {
    service: new RepositoryProvisioningService(provider, store),
    providerCalls,
    bindCalls,
    failCalls,
    provider,
    store,
  };
}

Deno.test("repository provisioning creates one private empty repository and binds the claimed PRE_PROJECT workspace", async () => {
  const test = harness();

  assertEquals(await test.service.provision(command), {
    ...repository,
    replayed: false,
  });
  assertEquals(test.providerCalls, [{
    idempotencyKey: command.idempotencyKey,
    repositoryName: command.repositoryName,
    visibility: "PRIVATE",
    defaultBranch: "main",
    bootstrap: "NONE",
  }]);
  assertEquals(test.bindCalls, [{
    operationId: "d1140000-0000-4000-8000-000000000001",
    expected: {
      websiteWorkspaceId: command.websiteWorkspaceId,
      websiteWorkContextId: command.websiteWorkContextId,
    },
    binding: repository,
  }]);
  assertEquals(test.failCalls, []);
});

Deno.test("repository provisioning replay returns the verified binding without calling the provider", async () => {
  const test = harness({ state: "REPLAY", binding: repository });

  assertEquals(await test.service.provision(command), {
    ...repository,
    replayed: true,
  });
  assertEquals(test.providerCalls, []);
  assertEquals(test.bindCalls, []);
});

Deno.test("repository provisioning fails closed while another claimant owns the operation", async () => {
  const test = harness({ state: "IN_PROGRESS" });

  await assertRejects(
    () => test.service.provision(command),
    Error,
    "REPOSITORY_PROVISIONING_IN_PROGRESS",
  );
  assertEquals(test.providerCalls, []);
  assertEquals(test.bindCalls, []);
});

Deno.test("repository provisioning hides failed and malformed store claims", async () => {
  const failed = harness();
  const failedStore: RepositoryProvisioningStore = {
    ...failed.store,
    claim: () => Promise.reject(new Error("database detail")),
  };
  await assertRejects(
    () =>
      new RepositoryProvisioningService(
        failed.provider,
        failedStore,
      ).provision(command),
    Error,
    "REPOSITORY_PROVISIONING_CLAIM_FAILED",
  );
  assertEquals(failed.providerCalls, []);
  assertEquals(failed.bindCalls, []);

  const malformed = harness();
  const malformedStore: RepositoryProvisioningStore = {
    ...malformed.store,
    claim: () =>
      Promise.resolve(
        { state: "CLAIMED", operationId: "bad" } as RepositoryProvisioningClaim,
      ),
  };
  await assertRejects(
    () =>
      new RepositoryProvisioningService(
        malformed.provider,
        malformedStore,
      ).provision(command),
    Error,
    "INVALID_REPOSITORY_PROVISIONING_CLAIM",
  );
  assertEquals(malformed.providerCalls, []);
  assertEquals(malformed.bindCalls, []);
});

Deno.test("repository provisioning rejects unverified provider metadata before binding", async () => {
  const test = harness();
  const provider: RepositoryProvisioningProvider = {
    provision: () =>
      Promise.resolve(
        { ...repository, visibility: "PUBLIC" } as unknown as RepositoryBinding,
      ),
  };
  const service = new RepositoryProvisioningService(provider, test.store);

  await assertRejects(
    () => service.provision(command),
    Error,
    "INVALID_REPOSITORY_PROVIDER_RESULT",
  );
  assertEquals(test.bindCalls, []);
  assertEquals(test.failCalls, [{
    operationId: "d1140000-0000-4000-8000-000000000001",
    code: "INVALID_REPOSITORY_PROVIDER_RESULT",
  }]);
});

Deno.test("repository provisioning never binds provider credentials", async () => {
  const test = harness();
  const provider: RepositoryProvisioningProvider = {
    provision: () =>
      Promise.resolve({
        ...repository,
        credential: "provider-secret",
      } as unknown as RepositoryBinding),
  };

  await assertRejects(
    () =>
      new RepositoryProvisioningService(provider, test.store).provision(
        command,
      ),
    Error,
    "INVALID_REPOSITORY_PROVIDER_RESULT",
  );
  assertEquals(test.bindCalls, []);
});

Deno.test("repository provisioning maps provider and binding failures to stable codes", async () => {
  const providerFailure = harness();
  const failingProvider: RepositoryProvisioningProvider = {
    provision: () => Promise.reject(new Error("upstream response with secret")),
  };
  await assertRejects(
    () =>
      new RepositoryProvisioningService(
        failingProvider,
        providerFailure.store,
      ).provision(command),
    Error,
    "REPOSITORY_PROVIDER_FAILED",
  );
  assertEquals(providerFailure.failCalls, [{
    operationId: "d1140000-0000-4000-8000-000000000001",
    code: "REPOSITORY_PROVIDER_FAILED",
  }]);

  const bindingFailure = harness();
  const failingStore: RepositoryProvisioningStore = {
    ...bindingFailure.store,
    bind: () => Promise.reject(new Error("database detail")),
  };
  await assertRejects(
    () =>
      new RepositoryProvisioningService(
        bindingFailure.provider,
        failingStore,
      ).provision(command),
    Error,
    "REPOSITORY_BINDING_FAILED",
  );
  assertEquals(bindingFailure.failCalls, [{
    operationId: "d1140000-0000-4000-8000-000000000001",
    code: "REPOSITORY_BINDING_FAILED",
  }]);
});

Deno.test("repository provisioning rejects browser-shaped or malformed commands before claiming", async () => {
  const test = harness();
  for (
    const invalid of [
      { ...command, repositoryName: "../customer" },
      { ...command, idempotencyKey: "bad" },
      { ...command, repositoryOwner: "browser-controlled" },
    ]
  ) {
    await assertRejects(
      () => test.service.provision(invalid as RepositoryProvisioningCommand),
      Error,
      "INVALID_REPOSITORY_PROVISIONING_COMMAND",
    );
  }
  assertEquals(test.providerCalls, []);
  assertEquals(test.bindCalls, []);
});

const v2Command: RepositoryProvisioningCommandV2 = Object.freeze({
  contractVersion: 2,
  websiteWorkspaceId: "d2110000-0000-4000-8000-000000000001",
  websiteWorkContextId: "d2120000-0000-4000-8000-000000000001",
  idempotencyKey: "d2130000-0000-4000-8000-000000000001",
  starter: Object.freeze({
    source: "lws-studio/lws-website-starter",
    version: "1.0.0",
    commitSha: "a".repeat(40),
    templateRepositoryId: "982451654",
  }),
});

const v2Repository: VerifiedRepositoryBindingV2 = Object.freeze({
  provider: "GITHUB",
  providerRepositoryId: "982451655",
  providerNodeId: "R_kgDONode123",
  owner: "lws-studio",
  name: "lws-web-d2120000000040008000000000000001",
  visibility: "PRIVATE",
  defaultBranch: "main",
  starterSource: v2Command.starter.source,
  starterVersion: v2Command.starter.version,
  starterCommitSha: v2Command.starter.commitSha,
  repositoryMarkerCommitSha: "b".repeat(40),
});

function v2Harness(
  claim: Awaited<ReturnType<RepositoryProvisioningStoreV2["claim"]>> = {
    state: "CLAIMED",
    operationId: "d2140000-0000-4000-8000-000000000001",
  },
) {
  const claimCalls: unknown[] = [];
  const providerCalls: unknown[] = [];
  const bindCalls: unknown[] = [];
  const failCalls: unknown[] = [];
  const provider: RepositoryProvisioningProviderV2 = {
    provision: (request) => {
      providerCalls.push(request);
      return Promise.resolve(v2Repository);
    },
  };
  const store: RepositoryProvisioningStoreV2 = {
    claim: (authority) => {
      claimCalls.push(authority);
      return Promise.resolve(claim);
    },
    bind: (operationId, expected, binding) => {
      bindCalls.push({ operationId, expected, binding });
      return Promise.resolve(binding);
    },
    fail: (operationId, code) => {
      failCalls.push({ operationId, code });
      return Promise.resolve();
    },
  };
  return {
    service: new RepositoryProvisioningServiceV2(provider, store),
    store,
    claimCalls,
    providerCalls,
    bindCalls,
    failCalls,
  };
}

Deno.test("repository provisioning V2 derives the canonical repository name from the work context", () => {
  assertEquals(
    repositoryNameForContext("0198ABCD-1234-7000-8000-0123456789AB"),
    "lws-web-0198abcd1234700080000123456789ab",
  );
  assertThrows(
    () => repositoryNameForContext("../customer"),
    Error,
    "INVALID_WEBSITE_WORK_CONTEXT_ID",
  );
});

Deno.test("repository provisioning V2 sends the exact template request and binds verified provenance", async () => {
  const test = v2Harness();

  assertEquals(await test.service.provision(v2Command), {
    ...v2Repository,
    replayed: false,
  });
  assertEquals(test.claimCalls, [{
    ...v2Command,
    repositoryName: v2Repository.name,
  }]);
  assertEquals(test.providerCalls, [{
    contractVersion: 2,
    operationId: "d2140000-0000-4000-8000-000000000001",
    websiteWorkContextId: v2Command.websiteWorkContextId,
    repositoryName: v2Repository.name,
    visibility: "PRIVATE",
    defaultBranch: "main",
    bootstrap: "GITHUB_TEMPLATE",
    starter: v2Command.starter,
  }]);
  assertEquals(test.bindCalls, [{
    operationId: "d2140000-0000-4000-8000-000000000001",
    expected: {
      websiteWorkspaceId: v2Command.websiteWorkspaceId,
      websiteWorkContextId: v2Command.websiteWorkContextId,
    },
    binding: v2Repository,
  }]);
  assertEquals(test.failCalls, []);
});

Deno.test("repository provisioning V2 replay returns only exact verified provenance", async () => {
  const test = v2Harness({ state: "REPLAY", binding: v2Repository });

  assertEquals(await test.service.provision(v2Command), {
    ...v2Repository,
    replayed: true,
  });
  assertEquals(test.providerCalls, []);
  assertEquals(test.bindCalls, []);
});

Deno.test("repository provisioning V2 rejects caller-controlled authority and malformed provider provenance", async () => {
  const test = v2Harness();
  for (
    const extra of [
      { repositoryOwner: "browser-owner" },
      { repositoryName: "browser-name" },
      { template: "browser/template" },
      { repositoryUrl: "https://example.test/repository" },
      { credential: "browser-secret" },
      { starter: { ...v2Command.starter, owner: "browser-owner" } },
      { starter: { ...v2Command.starter, commitSha: "not-a-commit" } },
    ]
  ) {
    await assertRejects(
      () =>
        test.service.provision({
          ...v2Command,
          ...extra,
        } as RepositoryProvisioningCommandV2),
      Error,
      "INVALID_REPOSITORY_PROVISIONING_COMMAND_V2",
    );
  }
  assertEquals(test.claimCalls, []);

  const malformed = v2Harness();
  const provider: RepositoryProvisioningProviderV2 = {
    provision: () =>
      Promise.resolve({
        ...v2Repository,
        providerNodeId: "",
      }),
  };
  await assertRejects(
    () =>
      new RepositoryProvisioningServiceV2(
        provider,
        {
          claim: () =>
            Promise.resolve({
              state: "CLAIMED",
              operationId: "d2140000-0000-4000-8000-000000000001",
            }),
          bind: () => Promise.resolve(v2Repository),
          fail: malformed.store.fail,
        },
      ).provision(v2Command),
    Error,
    "INVALID_REPOSITORY_PROVIDER_RESULT_V2",
  );
  assertEquals(malformed.failCalls, [{
    operationId: "d2140000-0000-4000-8000-000000000001",
    code: "INVALID_REPOSITORY_PROVIDER_RESULT_V2",
  }]);

  const credentialResult = v2Harness();
  await assertRejects(
    () =>
      new RepositoryProvisioningServiceV2(
        {
          provision: () =>
            Promise.resolve({
              ...v2Repository,
              credential: "provider-secret",
            } as unknown as VerifiedRepositoryBindingV2),
        },
        credentialResult.store,
      ).provision(v2Command),
    Error,
    "INVALID_REPOSITORY_PROVIDER_RESULT_V2",
  );
  assertEquals(credentialResult.bindCalls, []);
});
