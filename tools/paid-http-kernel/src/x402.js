function decodeFlexibleBase64(encoded, label) {
  const encodings = ["base64", "base64url"];
  for (const encoding of encodings) {
    try {
      return {
        encoding,
        text: Buffer.from(encoded, encoding).toString("utf8")
      };
    } catch {
      continue;
    }
  }
  throw new Error(`invalid ${label} base64 payload`);
}

function decodeJsonPayload(encoded, label) {
  const decoded = decodeFlexibleBase64(encoded, label);
  try {
    return {
      ...decoded,
      value: JSON.parse(decoded.text)
    };
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`invalid ${label} JSON payload: ${detail}`);
  }
}

function summarizeAccepts(accepts) {
  return {
    schemes: [...new Set(accepts.map((item) => item?.scheme).filter(Boolean))],
    networks: [...new Set(accepts.map((item) => item?.network).filter(Boolean))]
  };
}

function normalizeRequirement(value, encoded, source, encoding) {
  const accepts = Array.isArray(value?.accepts) ? value.accepts : [];
  const summary = summarizeAccepts(accepts);
  return {
    encoded,
    source,
    encoding,
    decoded: value,
    accepts,
    schemes: summary.schemes,
    networks: summary.networks,
    facilitator: value?.facilitator ?? value?.facilitatorUrl ?? null
  };
}

export function parseX402PaymentRequired(headerValue, bodyText = null, contentType = null) {
  if (headerValue) {
    const decoded = decodeJsonPayload(headerValue, "x402 payment requirement");
    return normalizeRequirement(decoded.value, headerValue, "header", decoded.encoding);
  }

  if (bodyText && contentType?.includes("json")) {
    try {
      const parsed = JSON.parse(bodyText);
      if (Array.isArray(parsed?.accepts)) {
        return normalizeRequirement(parsed, null, "body", null);
      }
    } catch {
      return null;
    }
  }

  return null;
}

export function parseX402PaymentResponse(headerValue) {
  if (!headerValue) {
    return null;
  }
  const decoded = decodeJsonPayload(headerValue, "x402 payment response");
  const value = decoded.value;
  return {
    encoded: headerValue,
    encoding: decoded.encoding,
    decoded: value,
    status: value?.status ?? value?.result ?? null,
    scheme: value?.scheme ?? null,
    network: value?.network ?? null,
    reference:
      value?.reference ??
      value?.txHash ??
      value?.transactionHash ??
      value?.settlementId ??
      null
  };
}

export function selectX402Requirement({ requirement, requestedSchemes = [] }) {
  if (!requirement) {
    return {
      accept: null,
      reason: "402 response did not include a parseable x402 payment requirement"
    };
  }

  if (!requirement.accepts.length) {
    return {
      accept: null,
      reason: "x402 payment requirement did not include any accepts entries"
    };
  }

  const accept =
    (requestedSchemes.length
      ? requirement.accepts.find((item) => requestedSchemes.includes(item?.scheme))
      : null) ?? requirement.accepts[0];

  if (!accept) {
    return {
      accept: null,
      reason: `no x402 scheme match for server accepts: ${requirement.schemes.join(", ") || "<none>"}`
    };
  }

  return {
    accept,
    reason: null
  };
}

export function buildX402PayloadTemplate(requirement, accept, adapter) {
  if (!requirement || !accept) {
    return null;
  }

  const acceptPayload = {};
  for (const key of [
    "scheme",
    "network",
    "asset",
    "payTo",
    "resource",
    "description",
    "maxAmountRequired",
    "mimeType"
  ]) {
    if (accept[key] != null) {
      acceptPayload[key] = accept[key];
    }
  }

  return {
    requirement: {
      source: requirement.source,
      schemes: requirement.schemes,
      networks: requirement.networks
    },
    accept: acceptPayload,
    payload: {
      adapterId: adapter?.id ?? null,
      fill: "scheme-specific x402 payment payload goes here"
    }
  };
}

export function encodeX402Payload(payload) {
  return Buffer.from(JSON.stringify(payload)).toString("base64");
}
