const PROFILE_PRESENTATION = Object.freeze({
  "OP-01": Object.freeze({ role: "owner", roleLabel: "Owner" }),
  "OP-02": Object.freeze({ role: "operations_manager", roleLabel: "Management / HR & Operations" }),
  "OP-03": Object.freeze({ role: "finance", roleLabel: "Finance" }),
});

function exactObjectKeys(value, keys) {
  return value && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every((key)=>Object.hasOwn(value, key));
}

export function operatorProfilePresentation(profile) {
  const keys = ["profile_code", "display_name", "email", "role", "role_label", "status"];
  const expected = PROFILE_PRESENTATION[profile?.profile_code];
  if (!exactObjectKeys(profile, keys)
    || typeof profile.display_name !== "string" || !profile.display_name
    || typeof profile.email !== "string" || profile.email !== profile.email.toLowerCase()
    || profile.status !== "ACTIVE"
    || !expected || profile.role !== expected.role || profile.role_label !== expected.roleLabel) {
    throw new Error("INVALID_OPERATOR_PROFILE");
  }
  return Object.freeze({
    code: profile.profile_code,
    displayName: profile.display_name,
    email: profile.email,
    roleLabel: profile.role_label,
  });
}

export function operatorProfileNameParts(displayName) {
  const [givenName, ...familyNames] = String(displayName || "").trim().split(/\s+/);
  return Object.freeze({ givenName, familyName: familyNames.join(" ") });
}

export function presentOperatorProfile(root, profile) {
  const presentation = operatorProfilePresentation(profile);
  const name = root.getElementById("operatorProfileName");
  const nameParts = operatorProfileNameParts(presentation.displayName);
  root.getElementById("operatorProfileCode").textContent = presentation.code;
  name.replaceChildren();
  name.setAttribute("aria-label", presentation.displayName);
  for (const [part, modifier] of [[nameParts.givenName, "given"], [nameParts.familyName, "family"]]) {
    if (!part) continue;
    const span = root.createElement("span");
    span.className = `operator-profile__name-part operator-profile__name-part--${modifier}`;
    span.setAttribute("aria-hidden", "true");
    span.textContent = part;
    name.append(span);
  }
  root.getElementById("operatorProfileEmail").textContent = presentation.email;
  root.getElementById("operatorProfileRole").textContent = presentation.roleLabel;
  root.getElementById("operatorProfileInitials").textContent = presentation.displayName
    .split(/\s+/).slice(0, 2).map((part)=>part[0]).join("").toUpperCase();
  root.getElementById("operatorProfileContent").hidden = false;
  root.getElementById("operatorProfileStatus").hidden = true;
  return presentation;
}

export async function initializeOperatorProfile(root, client) {
  const { data, error } = await client.rpc("get_current_operator_profile_v1", {});
  if (error) throw new Error(error.message);
  return presentOperatorProfile(root, data);
}