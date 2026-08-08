export type QuoteRequestStatus = "pending" | "approved" | "rejected";
export type ReviewAction = QuoteRequestStatus | "retry_confirmation";
export type EmailJobStatus = "pending" | "processing" | "sent" | "retry_wait" | "failed";

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
