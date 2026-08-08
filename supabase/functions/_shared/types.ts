export type QuoteRequestStatus = "pending" | "approved" | "rejected";
export type ReviewAction = QuoteRequestStatus | "retry_confirmation" | "send_intake_invitation" | "retry_intake_invitation";
export type EmailJobStatus = "pending" | "processing" | "sent" | "retry_wait" | "failed";
export type IntakeAction = "create" | "inspect" | "save_draft" | "submit";
export type IntakeStatus = "invited" | "in_progress" | "submitted" | "reviewed";

export interface SubmitQuotePayload {
  name: string;
  company?: string;
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
  company: string | null;
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
