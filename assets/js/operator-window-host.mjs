export function createOperatorWindowHost({ gate, locked, shell, sensitiveContent }) {
  let moduleController = null;

  function setModuleController(controller) {
    if (!controller || typeof controller.dispose !== "function") throw new TypeError("OPERATOR_MODULE_DISPOSE_REQUIRED");
    moduleController = controller;
  }

  function lock(reason = "WORKSPACE_INVALID") {
    try {
      moduleController?.dispose();
    } finally {
      moduleController = null;
      sensitiveContent?.replaceChildren();
      if (shell) shell.hidden = true;
      if (gate) gate.hidden = true;
      if (locked) {
        locked.hidden = false;
        locked.dataset.reason = reason;
      }
    }
  }

  return Object.freeze({ lock, setModuleController });
}
