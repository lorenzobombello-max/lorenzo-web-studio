export type QuoteRequestStatus = "pending" | "approved" | "rejected";
export type CustomerType = "individual" | "business";
export type EnterpriseValidationStatus = "format_valid_not_externally_verified" | "not_checked";
export type ReviewAction = QuoteRequestStatus | "retry_confirmation" | "send_intake_invitation" | "retry_intake_invitation";
export type EmailJobKind = "admin_notification" | "customer_confirmation" | "intake_invitation" | "intake_submitted_notification";
export type EmailJobStatus = "pending" | "processing" | "sent" | "retry_wait" | "failed";
export type IntakeAction =
  | "create"
  | "inspect"
  | "save_draft"
  | "submit"
  | "inspect_submitted_intake_admin"
  | "inspect_customer_pricing"
  | "inspect_admin_pricing";
export type IntakeStatus = "invited" | "in_progress" | "submitted" | "reviewed";

export interface SubmitQuotePayload {
  name: string;
  customer_type?: CustomerType;
  company?: string;
  enterprise_number?: string;
  vat_number?: string;
  billing_address?: string;
  billing_postal_code?: string;
  billing_city?: string;
  billing_country?: string;
  billing_email?: string;
  email: string;
  phone?: string;
  website_type: string;
  budget: string;
  timing: string;
  description: string;
  privacy_consent: boolean;
  website?: string; // Honeypot field.
}

export interface SanitizedQuotePayload {
  name: string;
  customer_type: CustomerType | null;
  company: string | null;
  enterprise_number: string | null;
  enterprise_validation_status: EnterpriseValidationStatus;
  vat_number: string | null;
  billing_address: string | null;
  billing_postal_code: string | null;
  billing_city: string | null;
  billing_country: string | null;
  billing_email: string | null;
  email: string;
  phone: string | null;
  website_type: string;
  budget: string;
  timing: string;
  description: string;
  privacy_consent: true;
  honeypotValue: string;
}

export interface ReviewActionPayload {
  token: string;
  action: ReviewAction;
}
