import {
  buildCredentialTemplate,
  buildRetryRequestHeaders
} from "./kernel.js";

export function buildSettlementAttempt({
  request,
  protocol,
  selection,
  policy = null,
  previousReceipt = null,
  metadata = null,
  attemptId = null
}) {
  if (!selection?.adapter) {
    throw new Error("settlement attempt requires a selected adapter");
  }

  return {
    executorId: selection.adapter.id,
    protocolFamily: protocol.family,
    request: {
      url: request.url,
      method: request.method,
      headers: request.headers ?? {},
      body: request.body ?? null
    },
    challenge: selection.challenge ?? null,
    requirement: selection.requirement ?? null,
    accept: selection.accept ?? null,
    credentialTemplate: buildCredentialTemplate({
      protocol,
      challenge: selection.challenge ?? null,
      requirement: selection.requirement ?? null,
      accept: selection.accept ?? null,
      adapter: selection.adapter
    }),
    policy,
    previousReceipt,
    metadata,
    attemptId
  };
}

export function normalizeSettlementSuccess({ protocol, result }) {
  return {
    ok: true,
    retryHeaders: buildRetryRequestHeaders({
      protocol,
      adapterResult: result
    }),
    paymentReceipt: result?.paymentReceipt ?? null,
    metadata: result?.metadata ?? null,
    source: result?.source ?? null
  };
}

export function normalizeSettlementFailure({
  retryable = false,
  category = "unknown",
  message,
  details = null
}) {
  if (!message) {
    throw new Error("settlement failure requires a message");
  }

  return {
    ok: false,
    retryable,
    category,
    message,
    details
  };
}
