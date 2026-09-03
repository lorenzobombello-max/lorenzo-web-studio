import { requireAuthorizedOperator, watchOperatorSession } from "./operator-auth-core.mjs?v=20260902-login-stability";
import { getOperatorClient } from "./operator-auth-client.mjs?v=20260902-login-stability";
import { mountStandaloneOperatorModule, resolveStandaloneOperatorModule } from "./operator-module-registry.mjs?v=20260903-trash-refresh-r1";
import { createOperatorWorkspaceChild } from "./operator-workspace-child.mjs?v=20260902-lifecycle-round2-hotfix1";
import { parseChildBootstrap } from "./operator-workspace-protocol.mjs?v=20260902-lifecycle-round2-hotfix1";
import { createOperatorWindowHost } from "./operator-window-host.mjs?v=20260902-login-stability";

const gate = document.getElementById("operatorWindowGate");
const locked = document.getElementById("operatorWindowLocked");
const shell = document.getElementById("operatorWindowShell");
const sensitiveContent = document.getElementById("operatorWindowSensitiveContent");
const identityBadge = document.getElementById("operatorWindowIdentity");
let childCoordinator = null;
let stopWatchingSession = null;
const windowHost = createOperatorWindowHost({ gate, locked, shell, sensitiveContent });
const lockWindow = windowHost.lock;

try {
  const bootstrap = parseChildBootstrap(window.location.href, window.location.origin);
  if (!bootstrap) throw new Error("INVALID_CHILD_BOOTSTRAP");

  const { client } = await getOperatorClient();
  const access = await requireAuthorizedOperator(client);
  if (access.status !== "authorized") throw new Error("OPERATOR_NOT_AUTHORIZED");

  const { data: identity, error: identityError } = await client.rpc("get_current_operator_identity_v1");
  if (identityError || identity?.status !== "ACTIVE") throw new Error("WORKSPACE_MODULE_NOT_AUTHORIZED");
  const descriptor = resolveStandaloneOperatorModule(bootstrap.moduleKey);
  if (!descriptor) throw new Error("WORKSPACE_MODULE_NOT_ENABLED");

  const { data: joinedWorkspace, error: joinError } = await client.rpc("join_operator_workspace_v1", {
    p_workspace_id: bootstrap.workspaceId,
    p_epoch: bootstrap.epoch,
    p_window_id: bootstrap.windowId,
    p_module_key: bootstrap.moduleKey,
    p_slot_key: bootstrap.slotKey,
  });
  if (joinError || joinedWorkspace?.joined !== true || joinedWorkspace?.window_id !== bootstrap.windowId
    || joinedWorkspace?.module_key !== bootstrap.moduleKey || joinedWorkspace?.slot_key !== bootstrap.slotKey) {
    throw new Error("WORKSPACE_JOIN_REJECTED");
  }

  childCoordinator = createOperatorWorkspaceChild({
    client,
    bootstrap,
    joinedWorkspace,
    onInvalidate: (moduleKey)=>moduleKey === bootstrap.moduleKey && sensitiveContent.operatorModuleController?.refresh(),
    onLock: lockWindow,
  });
  const moduleController = await mountStandaloneOperatorModule({
    moduleKey: bootstrap.moduleKey,
    root: document,
    client,
    identity,
    onInvalidate: (moduleKey)=>childCoordinator.invalidate(moduleKey),
    onAuthorizationFailure: ()=>childCoordinator.lock("WORKSPACE_MODULE_NOT_AUTHORIZED"),
  });
  sensitiveContent.operatorModuleController = moduleController;
  windowHost.setModuleController(moduleController);
  document.title = `${descriptor.displayName} | Lorenzo Web Solutions`;
  identityBadge.textContent = String(identity.role || "OPERATOR").replaceAll("_", " ").toUpperCase();
  gate.hidden = true;
  shell.hidden = false;
  stopWatchingSession = watchOperatorSession(client, ()=>{}, ()=>childCoordinator.lock("AUTH_SIGNED_OUT"));
  window.opener = null;
} catch (error) {
  lockWindow(error?.message || "WORKSPACE_INVALID");
}

window.addEventListener("pagehide", ()=>{
  stopWatchingSession?.();
  childCoordinator?.dispose();
}, { once: true });