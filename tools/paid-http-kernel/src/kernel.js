import {
  encodePaymentCredential,
  parsePaymentChallenges,
  parsePaymentReceipt
} from "./paymentauth.js";
import {
  buildX402PayloadTemplate,
  encodeX402Payload,
  parseX402PaymentRequired,
  parseX402PaymentResponse,
  selectX402Requirement
} from "./x402.js";

export function normalizeHeaders(headers) {
  const normalized = {};
  for (const [key, value] of Object.entries(headers ?? {})) {
    normalized[String(key).toLowerCase()] = value;
  }
  return normalized;
}

export function parseProblemDetails(bodyText, contentType) {
  if (!bodyText || !contentType?.includes("json")) {
    return null;
  }
  try {
    const parsed = JSON.parse(bodyText);
    if (typeof parsed !== "object" || parsed == null) {
      return null;
    }
    const candidate = {
      type: parsed.type ?? null,
      title: parsed.title ?? null,
      status: parsed.status ?? null,
      detail: parsed.detail ?? null,
      challengeId: parsed.challengeId ?? null
    };
    return Object.values(candidate).some((value) => value != null) ? candidate : null;
  } catch {
    return null;
  }
}

export function normalizeDiscoveryDocument(document, endpoint) {
  const method = (endpoint.method ?? "GET").toLowerCase();
  const operation = document?.paths?.[endpoint.path]?.[method] ?? null;
  return {
    openapi: document?.openapi ?? null,
    info: document?.info ?? null,
    serviceInfo: document?.["x-service-info"] ?? null,
    operation: operation
      ? {
          path: endpoint.path,
          method,
          summary: operation.summary ?? null,
          paymentInfo: operation["x-payment-info"] ?? null,
          has402Response: Boolean(operation.responses?.["402"]),
          hasRequestBody: Boolean(operation.requestBody)
        }
      : null
  };
}

export function parseProtocolArtifacts({ protocol, response }) {
  if (protocol.family === "x402") {
    return {
      challenges: [],
      requirement: parseX402PaymentRequired(
        response.headers?.[protocol.challengeHeader],
        response.bodyText,
        response.headers?.["content-type"]
      ),
      receipt: parseX402PaymentResponse(response.headers?.[protocol.receiptHeader])
    };
  }

  if (protocol.family === "paymentauth") {
    return {
      challenges: parsePaymentChallenges(response.headers?.[protocol.challengeHeader]),
      requirement: null,
      receipt: parsePaymentReceipt(response.headers?.[protocol.receiptHeader])
    };
  }

  return {
    challenges: [],
    requirement: null,
    receipt: null
  };
}

export function selectPaymentAdapter({ protocol, challenges = [], requirement = null }) {
  const adapter = protocol.adapter ?? null;
  if (!adapter) {
    return {
      adapter: null,
      challenge: null,
      requirement: null,
      accept: null,
      reason: "protocol does not declare an adapter boundary"
    };
  }

  if (protocol.family === "x402") {
    const selection = selectX402Requirement({
      requirement,
      requestedSchemes: protocol.requestedSchemes ?? []
    });
    return {
      adapter,
      challenge: null,
      requirement,
      accept: selection.accept,
      reason: selection.reason
    };
  }

  if (!challenges.length) {
    return {
      adapter,
      challenge: null,
      requirement: null,
      accept: null,
      reason: "response did not include a Payment challenge"
    };
  }

  const requested = protocol.requestedMethods?.length ? protocol.requestedMethods : [];
  const challenge = challenges.find((item) => requested.includes(item.method)) ?? null;

  if (!challenge) {
    const advertised = [...new Set(challenges.map((item) => item.method).filter(Boolean))];
    return {
      adapter,
      challenge: null,
      requirement: null,
      accept: null,
      reason: `no adapter match for server methods: ${advertised.join(", ") || "<none>"}`
    };
  }

  return {
    adapter,
    challenge,
    requirement: null,
    accept: null,
    reason: null
  };
}

export function buildCredentialTemplate({ protocol, challenge, requirement, accept, adapter }) {
  if (protocol.family === "x402") {
    return buildX402PayloadTemplate(requirement, accept, adapter);
  }

  if (!challenge) {
    return null;
  }

  const challengePayload = {
    id: challenge.id,
    realm: challenge.realm,
    method: challenge.method,
    intent: challenge.intent,
    request: challenge.request?.encoded ?? null
  };

  for (const optionalKey of ["expires", "digest"]) {
    if (challenge[optionalKey]) {
      challengePayload[optionalKey] = challenge[optionalKey];
    }
  }
  if (challenge.opaque?.encoded) {
    challengePayload.opaque = challenge.opaque.encoded;
  }

  return {
    challenge: challengePayload,
    payload: {
      adapterId: adapter?.id ?? null,
      fill: "method-specific payment payload goes here"
    }
  };
}

export function buildRetryRequestHeaders({ protocol, adapterResult }) {
  const parsed = adapterResult ?? {};
  if (parsed.headers && typeof parsed.headers === "object") {
    return normalizeHeaders(parsed.headers);
  }

  if (protocol.family === "paymentauth") {
    const credential = parsed.credential ?? null;
    const authorization =
      parsed.authorization ??
      (credential ? `Payment ${encodePaymentCredential(credential)}` : null);
    if (!authorization) {
      throw new Error(
        "paymentauth adapter output must include headers, authorization, or credential"
      );
    }
    return {
      [protocol.requestHeader ?? "authorization"]: authorization
    };
  }

  if (protocol.family === "x402") {
    const paymentSignature =
      parsed.paymentSignature ??
      parsed.payment_signature ??
      parsed["payment-signature"] ??
      null;
    const payload = parsed.payload ?? parsed.paymentPayload ?? null;
    const encoded = paymentSignature ?? (payload ? encodeX402Payload(payload) : null);
    if (!encoded) {
      throw new Error(
        "x402 adapter output must include headers, paymentSignature, or payload"
      );
    }
    return {
      [protocol.requestHeader ?? "payment-signature"]: encoded
    };
  }

  throw new Error(`unsupported adapter protocol family: ${protocol.family}`);
}

export async function executePaidRequest({
  request,
  requestHeaders,
  fetchImpl = fetch
}) {
  const finalRequestHeaders = {
    "content-type": "application/json",
    ...(requestHeaders ?? {})
  };

  const response = await fetchImpl(request.url, {
    method: request.method,
    headers: finalRequestHeaders,
    body: request.body == null ? undefined : JSON.stringify(request.body)
  });

  return {
    status: response.status,
    ok: response.ok,
    headers: normalizeHeaders(Object.fromEntries(response.headers.entries())),
    bodyText: await response.text(),
    requestHeaders: finalRequestHeaders
  };
}

export async function runPaidHttpFlow({
  request,
  protocol,
  probeResponse = null,
  retryResponse = null,
  adapterResult = null,
  fetchImpl = fetch
}) {
  const initialResponse =
    probeResponse ??
    (await executePaidRequest({
      request,
      requestHeaders: request.headers,
      fetchImpl
    }));

  const initialArtifacts = parseProtocolArtifacts({
    protocol,
    response: initialResponse
  });
  const selection = selectPaymentAdapter({
    protocol,
    challenges: initialArtifacts.challenges,
    requirement: initialArtifacts.requirement
  });
  const problem = parseProblemDetails(
    initialResponse.bodyText,
    initialResponse.headers?.["content-type"]
  );
  const credentialTemplate = buildCredentialTemplate({
    protocol,
    challenge: selection.challenge,
    requirement: selection.requirement,
    accept: selection.accept,
    adapter: selection.adapter
  });

  let stage = "probe-complete";
  let blocked = false;
  let reason = null;
  let finalResponse = initialResponse;

  if (initialResponse.status === 402) {
    stage = "challenge-received";
    if (selection.reason) {
      blocked = true;
      reason = selection.reason;
    } else if (!adapterResult) {
      blocked = true;
      reason = "adapter result required before retry";
    } else {
      const retryHeaders = buildRetryRequestHeaders({
        protocol,
        adapterResult
      });
      finalResponse =
        retryResponse ??
        (await executePaidRequest({
          request,
          requestHeaders: retryHeaders,
          fetchImpl
        }));
      stage = finalResponse.ok ? "settled" : "settled-response-error";
    }
  } else if (selection.challenge || selection.accept) {
    blocked = true;
    stage = "unexpected-auth-shape";
    reason =
      protocol.family === "x402"
        ? "received an x402 payment requirement without a 402 status"
        : "received a Payment challenge without a 402 status";
  }

  const finalArtifacts = parseProtocolArtifacts({
    protocol,
    response: finalResponse
  });

  return {
    status: finalResponse.status,
    ok: finalResponse.ok,
    blocked,
    reason,
    stage,
    protocol: {
      family: protocol.family,
      challenges: initialArtifacts.challenges,
      requirement: initialArtifacts.requirement,
      selectedAdapter: selection.adapter,
      selectedChallenge: selection.challenge,
      selectedRequirement: selection.requirement,
      selectedAccept: selection.accept,
      credentialTemplate,
      problem,
      receipt: finalArtifacts.receipt
    },
    responses: {
      initial: initialResponse,
      final: finalResponse
    }
  };
}
