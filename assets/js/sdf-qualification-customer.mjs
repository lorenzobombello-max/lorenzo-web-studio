const text = (value) => typeof value === "string" ? value.trim() : "";

export function buildSdfQualificationCustomer(intake = {}) {
  const customer = intake.customer && typeof intake.customer === "object" ? intake.customer : {};
  const name = text(customer.name);
  const createdAt = text(intake.request_created_at);
  const createdDate = createdAt && !Number.isNaN(Date.parse(createdAt))
    ? new Intl.DateTimeFormat("nl-BE", { dateStyle: "long", timeZone: "Europe/Brussels" }).format(new Date(createdAt))
    : "";
  return {
    greeting: name ? `Beste ${name},` : "Beste klant,",
    rows: [
      ["name", "Naam", name],
      ["company", "Bedrijf", text(customer.company)],
      ["email", "E-mail", text(customer.email)],
      ["phone", "Telefoon", text(customer.phone)],
      ["service", "Dienst", "Slimme Documentenflow"],
      ["request_created_at", "Aanvraagdatum", createdDate],
      ["support_reference", "Dossierreferentie", text(intake.support_reference)],
    ].filter(([, , value]) => value),
  };
}

export function renderSdfQualificationCustomer(root, intake) {
  const presentation = buildSdfQualificationCustomer(intake);
  root.getElementById("sdfCustomerGreeting").textContent = presentation.greeting;
  const values = new Map(presentation.rows.map(([field, , value]) => [field, value]));
  root.querySelectorAll("#sdfCustomerDossier [data-customer-field]").forEach((row) => {
    const value = values.get(row.dataset.customerField) || "";
    row.hidden = !value;
    row.querySelector("dd").textContent = value;
  });
  return presentation;
}