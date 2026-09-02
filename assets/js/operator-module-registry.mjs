const MODULE_KEY = /^[a-z][a-z0-9-]{0,47}$/;
const SLOT_KEY = /^[a-z][a-z0-9-]{0,47}$/;
export const REQUIRED_MULTI_SCREEN_MODULES = Object.freeze(["messages", "calendar", "recruitment", "workforce", "finance", "dossiers"]);

const descriptors = [
  {
    moduleKey: "dossiers",
    displayName: "Dossiers",
    route: "/operator/dashboard/?module=dossiers",
    currentlyImplemented: true,
    initializer: "initializeOperatorDossiers",
    serverAuthority: "bounded commercial-operator-command dossier actions and object-authorized dossier RPCs",
    standaloneAllowed: true,
    multiScreenAllowed: true,
    singletonPolicy: "module-slot",
    desktopMultiWindowAllowed: true,
    blockReason: null,
  },
  {
    moduleKey: "intake",
    displayName: "Intake opvolging",
    route: "/operator/dashboard/?module=intake",
    currentlyImplemented: true,
    initializer: "startOperatorDashboard",
    serverAuthority: "commercial-operator-command intake lifecycle actions",
    standaloneAllowed: false,
    multiScreenAllowed: false,
    singletonPolicy: "module-slot",
    desktopMultiWindowAllowed: false,
    blockReason: "MULTI_SCREEN_BLOCKED_BY_LEGACY_COUPLING: dossier workspace and mixed Website/SDF intake projections",
  },
  {
    moduleKey: "finance",
    displayName: "Financieel",
    route: "/operator/dashboard/?module=finance",
    currentlyImplemented: true,
    initializer: "initializeOperatorFinance",
    serverAuthority: "owner-only finance portfolio, expense, supplier document, and document inbox RPCs",
    standaloneAllowed: true,
    multiScreenAllowed: true,
    singletonPolicy: "module-slot",
    desktopMultiWindowAllowed: true,
    blockReason: null,
  },
  {
    moduleKey: "workforce",
    displayName: "Personeel",
    route: "/operator/dashboard/?module=workforce",
    currentlyImplemented: true,
    initializer: "initializeOperatorWorkforce",
    serverAuthority: "list_operator_workforce_v1 and workforce workspace module authority",
    standaloneAllowed: true,
    multiScreenAllowed: true,
    singletonPolicy: "module-slot",
    desktopMultiWindowAllowed: true,
    blockReason: null,
  },
  {
    moduleKey: "recruitment",
    displayName: "Rekrutering",
    route: "/operator/dashboard/?module=recruitment",
    currentlyImplemented: true,
    initializer: "initializeOperatorRecruitment",
    serverAuthority: "Recruitment RPCs and owner-only workspace module authority",
    standaloneAllowed: true,
    multiScreenAllowed: true,
    singletonPolicy: "module-slot",
    desktopMultiWindowAllowed: true,
    blockReason: null,
  },
  {
    moduleKey: "messages",
    displayName: "Berichtenkamer",
    route: "/operator/dashboard/?module=messages",
    currentlyImplemented: true,
    initializer: "initializeOperatorMessages",
    serverAuthority: "Operator message RPCs and workspace join authority",
    standaloneAllowed: true,
    multiScreenAllowed: true,
    singletonPolicy: "module-slot",
    desktopMultiWindowAllowed: true,
    blockReason: null,
  },
  {
    moduleKey: "calendar",
    displayName: "Kalender",
    route: "/operator/dashboard/?module=calendar",
    currentlyImplemented: true,
    initializer: "initializeOperatorCalendar",
    serverAuthority: "get_operator_calendar_v1 and workspace module authority",
    standaloneAllowed: true,
    multiScreenAllowed: true,
    singletonPolicy: "module-slot",
    desktopMultiWindowAllowed: true,
    blockReason: null,
  },
];

export const OPERATOR_MODULE_DESCRIPTORS = Object.freeze(descriptors.map((descriptor)=>Object.freeze(descriptor)));
const registry = new Map(OPERATOR_MODULE_DESCRIPTORS.map((descriptor)=>[descriptor.moduleKey, descriptor]));
const standaloneInitializers = new Map([
  ["dossiers", async ({ root, client, identity, onAuthorizationFailure })=>{
    const { initializeOperatorDossiers } = await import("./operator-dossiers.mjs?v=20260902-dossiers-ux-restoration");
    const controller = initializeOperatorDossiers(root, client, identity, { onAuthorizationFailure });
    return {
      dispose: ()=>controller.dispose(),
      refresh: ()=>controller.refresh(),
      setInvalidationPublisher: ()=>{},
    };
  }],
  ["messages", async ({ root, client, identity, onInvalidate })=>{
    const { initializeOperatorMessages } = await import("./operator-messages.mjs?v=20260902-phase2c");
    const controller = initializeOperatorMessages(root, client, identity, { onInvalidate });
    return {
      dispose: ()=>controller?.destroy(),
      refresh: ()=>controller?.refresh(),
      setInvalidationPublisher: (publisher)=>controller?.setInvalidationPublisher(publisher),
    };
  }],
  ["calendar", async ({ root, client, identity, onAuthorizationFailure })=>{
    const { initializeOperatorCalendar } = await import("./operator-calendar.mjs?v=20260902-phase2e");
    const controller = initializeOperatorCalendar(root, client, identity, { onAuthorizationFailure });
    return {
      dispose: ()=>controller.dispose(),
      refresh: ()=>controller.reload(),
      setInvalidationPublisher: ()=>{},
    };
  }],
  ["recruitment", async ({ root, client, identity, onAuthorizationFailure })=>{
    const { initializeOperatorRecruitment } = await import("./operator-recruitment.mjs?v=20260902-phase2f");
    const controller = initializeOperatorRecruitment(root, client, identity, { onAuthorizationFailure });
    return {
      dispose: ()=>controller.dispose(),
      refresh: ()=>controller.refresh(),
      setInvalidationPublisher: ()=>{},
    };
  }],
  ["workforce", async ({ root, client, identity, onAuthorizationFailure })=>{
    const { initializeOperatorWorkforce } = await import("./operator-workforce.mjs?v=20260902-login-stability");
    const controller = initializeOperatorWorkforce(root, client, identity, { onAuthorizationFailure });
    return {
      dispose: ()=>controller.dispose(),
      refresh: ()=>controller.refresh(),
      setInvalidationPublisher: ()=>{},
    };
  }],
  ["finance", async ({ root, client, identity, onAuthorizationFailure })=>{
    const { initializeOperatorFinance } = await import("./operator-finance.mjs?v=20260902-phase2h1");
    const controller = initializeOperatorFinance(root, client, identity, { onAuthorizationFailure });
    return {
      dispose: ()=>controller.dispose(),
      refresh: ()=>controller.refresh(),
      setInvalidationPublisher: ()=>{},
    };
  }],
]);

export function validOperatorModuleKey(value) {
  return MODULE_KEY.test(String(value || ""));
}

export function validOperatorSlotKey(value) {
  return SLOT_KEY.test(String(value || ""));
}

export function getOperatorModuleDescriptor(moduleKey) {
  return registry.get(String(moduleKey || "")) || null;
}

export function resolveStandaloneOperatorModule(moduleKey) {
  const descriptor = getOperatorModuleDescriptor(moduleKey);
  return descriptor?.standaloneAllowed && descriptor.multiScreenAllowed ? descriptor : null;
}

export async function mountStandaloneOperatorModule({ moduleKey, root, client, identity, onInvalidate = ()=>{}, onAuthorizationFailure = ()=>{} }) {
  const descriptor = resolveStandaloneOperatorModule(moduleKey);
  if (!descriptor) throw new Error("OPERATOR_MODULE_STANDALONE_DISABLED");
  const template = root.getElementById(`operatorModuleTemplate-${moduleKey}`);
  const host = root.getElementById("operatorWindowSensitiveContent");
  if (!template || !host) throw new Error("OPERATOR_MODULE_TEMPLATE_MISSING");
  host.replaceChildren(template.content.cloneNode(true));

  const initialize = standaloneInitializers.get(moduleKey);
  if (!initialize) throw new Error("OPERATOR_MODULE_INITIALIZER_MISSING");
  try {
    return Object.freeze({ descriptor, ...await initialize({ root, client, identity, onInvalidate, onAuthorizationFailure }) });
  } catch (error) {
    host.replaceChildren();
    throw error;
  }
}
