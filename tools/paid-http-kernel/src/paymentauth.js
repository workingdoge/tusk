function decodeBase64Url(value, label) {
  try {
    return Buffer.from(value, "base64url").toString("utf8");
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`invalid ${label} base64url payload: ${detail}`);
  }
}

function decodeJsonBase64Url(value, label) {
  const text = decodeBase64Url(value, label);
  try {
    return JSON.parse(text);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`invalid ${label} JSON payload: ${detail}`);
  }
}

function pushAuthParam(params, key, value) {
  if (params[key] == null) {
    params[key] = value;
    return;
  }
  if (Array.isArray(params[key])) {
    params[key].push(value);
    return;
  }
  params[key] = [params[key], value];
}

function unquoteHeaderValue(value) {
  if (!value.startsWith('"') || !value.endsWith('"')) {
    return value;
  }

  let result = "";
  let escaping = false;
  for (let index = 1; index < value.length - 1; index += 1) {
    const char = value[index];
    if (escaping) {
      result += char;
      escaping = false;
      continue;
    }
    if (char === "\\") {
      escaping = true;
      continue;
    }
    result += char;
  }
  return result;
}

function parseAuthParams(segment) {
  const params = {};
  let index = 0;
  while (index < segment.length) {
    while (index < segment.length && /[\s,]/.test(segment[index])) {
      index += 1;
    }
    if (index >= segment.length) {
      break;
    }

    const equalsIndex = segment.indexOf("=", index);
    if (equalsIndex === -1) {
      throw new Error(`invalid auth-param segment: ${segment.slice(index)}`);
    }

    const key = segment.slice(index, equalsIndex).trim();
    if (!key) {
      throw new Error(`missing auth-param key in segment: ${segment}`);
    }

    index = equalsIndex + 1;
    let value = "";

    if (segment[index] === '"') {
      let end = index + 1;
      let escaping = false;
      while (end < segment.length) {
        const char = segment[end];
        if (escaping) {
          escaping = false;
          end += 1;
          continue;
        }
        if (char === "\\") {
          escaping = true;
          end += 1;
          continue;
        }
        if (char === '"') {
          break;
        }
        end += 1;
      }
      if (end >= segment.length) {
        throw new Error(`unterminated quoted value in segment: ${segment}`);
      }
      value = unquoteHeaderValue(segment.slice(index, end + 1));
      index = end + 1;
    } else {
      let end = index;
      while (end < segment.length && segment[end] !== ",") {
        end += 1;
      }
      value = segment.slice(index, end).trim();
      index = end;
    }

    pushAuthParam(params, key, value);
  }
  return params;
}

function splitPaymentChallenges(headerValue) {
  if (!headerValue) {
    return [];
  }

  const value = headerValue.trim();
  if (!value) {
    return [];
  }

  const challenges = [];
  let start = 0;
  let inQuotes = false;
  let escaping = false;

  for (let index = 0; index < value.length; index += 1) {
    const char = value[index];
    if (escaping) {
      escaping = false;
      continue;
    }
    if (char === "\\") {
      escaping = inQuotes;
      continue;
    }
    if (char === '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (inQuotes || char !== ",") {
      continue;
    }

    let lookahead = index + 1;
    while (lookahead < value.length && /\s/.test(value[lookahead])) {
      lookahead += 1;
    }
    if (value.startsWith("Payment", lookahead)) {
      const candidate = value.slice(start, index).trim();
      if (candidate) {
        challenges.push(candidate);
      }
      start = lookahead;
    }
  }

  const tail = value.slice(start).trim();
  if (tail) {
    challenges.push(tail);
  }
  return challenges.filter((item) => item.startsWith("Payment"));
}

function normalizeDecodedJsonParam(encoded, label) {
  if (!encoded) {
    return null;
  }
  return {
    encoded,
    decoded: decodeJsonBase64Url(encoded, label)
  };
}

export function parsePaymentChallenges(headerValue) {
  return splitPaymentChallenges(headerValue).map((challengeText) => {
    const paramsText = challengeText.slice("Payment".length).trim();
    const params = parseAuthParams(paramsText);
    const request = normalizeDecodedJsonParam(params.request, "request");
    const opaque = normalizeDecodedJsonParam(params.opaque, "opaque");
    const missingRequired = ["id", "realm", "method", "intent", "request"].filter(
      (key) => params[key] == null
    );

    return {
      raw: challengeText,
      scheme: "Payment",
      id: params.id ?? null,
      realm: params.realm ?? null,
      method: params.method ?? null,
      intent: params.intent ?? null,
      expires: params.expires ?? null,
      digest: params.digest ?? null,
      description: params.description ?? null,
      params,
      request,
      opaque,
      missingRequired
    };
  });
}

export function parsePaymentReceipt(headerValue) {
  if (!headerValue) {
    return null;
  }
  const decoded = decodeJsonBase64Url(headerValue, "payment receipt");
  return {
    encoded: headerValue,
    decoded,
    status: decoded.status ?? null,
    method: decoded.method ?? null,
    timestamp: decoded.timestamp ?? null,
    reference: decoded.reference ?? null
  };
}

export function encodePaymentCredential(credential) {
  return Buffer.from(JSON.stringify(credential)).toString("base64url");
}
