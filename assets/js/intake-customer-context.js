const APPLICATION_REFERENCE = /^LWS-AAN-[0-9]{4}-[0-9]{4}$/;

export function websiteIntakeContextPresentation({ request, intake, application } = {}) {
  const display = (value, fallback) => typeof value === "string" && value.trim() ? value.trim() : fallback;
  const createdAt = Number.isFinite(Date.parse(request?.created_at))
    ? new Date(request.created_at).toLocaleDateString("nl-BE", { dateStyle: "long", timeZone: "Europe/Brussels" })
    : "Niet beschikbaar";
  const status = intake?.status === "in_progress" ? "Concept hersteld"
    : intake?.status === "submitted" ? "Verzonden"
    : intake?.status === "reviewed" ? "Verwerkt"
    : "Nog niet gestart";
  return {
    name: display(request?.name, "Klant"),
    email: display(request?.email, "Niet beschikbaar"),
    service: "Website",
    requestedAt: createdAt,
    reference: APPLICATION_REFERENCE.test(String(application?.applicationReference || ""))
      ? application.applicationReference
      : "Beschikbaar na indiening",
    projectType: display(request?.website_type, "Websiteproject"),
    status,
  };
}