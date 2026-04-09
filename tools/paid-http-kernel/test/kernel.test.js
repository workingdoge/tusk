import test from "node:test";
import assert from "node:assert/strict";

import {
  buildCredentialTemplate,
  buildRetryRequestHeaders,
  normalizeDiscoveryDocument,
  parsePaymentChallenges,
  parsePaymentReceipt,
  parseProtocolArtifacts,
  parseX402PaymentRequired,
  parseX402PaymentResponse,
  runPaidHttpFlow,
  selectPaymentAdapter
} from "../src/index.js";

const requestPayload =
  "eyJhbW91bnQiOiIwLjA1IiwiYXNzZXQiOiJVU0QiLCJyZXNvdXJjZSI6Imh0dHBzOi8vYWdlbnRzLmFsbGl1bS5zby9hcGkvdjEvZGV2ZWxvcGVyL3dhbGxldC90cmFuc2FjdGlvbnMiLCJkZXNjcmlwdG9yIjoiYWxsaXVtIHdhbGxldCB0eCBoaXN0b3J5In0";
const opaquePayload =
  "eyJhdHRlbXB0IjoiZmlyc3QtcHJvYmUiLCJwcm92aWRlciI6ImFsbGl1bSJ9";
const receiptPayload =
  "eyJpZCI6InJlY2VpcHRfMTIzIiwibWV0aG9kIjoidGVtcG8iLCJzdGF0dXMiOiJhY2NlcHRlZCIsInRpbWVzdGFtcCI6IjIwMjYtMDQtMDVUMjI6MDA6MDBaIiwicmVmZXJlbmNlIjoidGVtcG9fdHhfMTIzIn0";
const x402RequirementPayload = Buffer.from(
  JSON.stringify({
    accepts: [
      {
        scheme: "exact",
        network: "eip155:8453",
        asset: "USDC",
        payTo: "0xabc123",
        maxAmountRequired: "0.05"
      }
    ],
    facilitator: "https://pay.example.com"
  })
).toString("base64");
const x402ResponsePayload = Buffer.from(
  JSON.stringify({
    status: "settled",
    scheme: "exact",
    network: "eip155:8453",
    transactionHash: "0xabc123",
    reference: "x402_demo_tx_001"
  })
).toString("base64");

test("parses Payment challenges and receipts", () => {
  const header = `Payment id="challenge_123", realm="agents.allium.so", method="tempo", intent="charge", request="${requestPayload}", opaque="${opaquePayload}", Payment id="challenge_124", realm="agents.allium.so", method="stripe", intent="charge", request="${requestPayload}"`;
  const challenges = parsePaymentChallenges(header);

  assert.equal(challenges.length, 2);
  assert.equal(challenges[0].method, "tempo");
  assert.equal(
    challenges[0].request.decoded.resource,
    "https://agents.allium.so/api/v1/developer/wallet/transactions"
  );
  assert.equal(challenges[0].opaque.decoded.provider, "allium");

  const receipt = parsePaymentReceipt(receiptPayload);
  assert.equal(receipt.reference, "tempo_tx_123");
});

test("parses x402 requirement and receipt payloads", () => {
  const requirement = parseX402PaymentRequired(x402RequirementPayload);
  assert.deepEqual(requirement.schemes, ["exact"]);
  assert.equal(requirement.accepts[0].network, "eip155:8453");

  const receipt = parseX402PaymentResponse(x402ResponsePayload);
  assert.equal(receipt.reference, "x402_demo_tx_001");
  assert.equal(receipt.scheme, "exact");
});

test("normalizes discovery documents", () => {
  const document = {
    openapi: "3.1.0",
    info: { title: "Allium Agent API", version: "2026-04-05" },
    "x-service-info": { publisher: "Allium" },
    paths: {
      "/api/v1/developer/wallet/transactions": {
        post: {
          summary: "Fetch wallet transactions",
          "x-payment-info": {
            methods: ["tempo", "stripe"]
          },
          requestBody: { required: true },
          responses: {
            "402": { description: "Payment required" }
          }
        }
      }
    }
  };

  const summary = normalizeDiscoveryDocument(document, {
    path: "/api/v1/developer/wallet/transactions",
    method: "POST"
  });

  assert.deepEqual(summary.operation.paymentInfo.methods, ["tempo", "stripe"]);
  assert.equal(summary.operation.has402Response, true);
});

test("selects paymentauth and x402 adapters and builds credential templates", () => {
  const paymentauthProtocol = {
    family: "paymentauth",
    challengeHeader: "www-authenticate",
    requestHeader: "authorization",
    receiptHeader: "payment-receipt",
    requestedMethods: ["tempo"],
    adapter: {
      id: "tempo-charge"
    }
  };
  const paymentauthResponse = {
    headers: {
      "www-authenticate": `Payment id="challenge_123", realm="agents.allium.so", method="tempo", intent="charge", request="${requestPayload}", opaque="${opaquePayload}"`
    },
    bodyText: ""
  };
  const paymentauthArtifacts = parseProtocolArtifacts({
    protocol: paymentauthProtocol,
    response: paymentauthResponse
  });
  const paymentauthSelection = selectPaymentAdapter({
    protocol: paymentauthProtocol,
    challenges: paymentauthArtifacts.challenges
  });
  assert.equal(paymentauthSelection.adapter.id, "tempo-charge");
  assert.equal(paymentauthSelection.challenge.method, "tempo");

  const paymentauthTemplate = buildCredentialTemplate({
    protocol: paymentauthProtocol,
    challenge: paymentauthSelection.challenge,
    requirement: null,
    accept: null,
    adapter: paymentauthSelection.adapter
  });
  assert.equal(paymentauthTemplate.challenge.method, "tempo");

  const x402Protocol = {
    family: "x402",
    challengeHeader: "payment-required",
    requestHeader: "payment-signature",
    receiptHeader: "payment-response",
    requestedSchemes: ["exact"],
    adapter: {
      id: "x402-charge"
    }
  };
  const x402Artifacts = parseProtocolArtifacts({
    protocol: x402Protocol,
    response: {
      headers: {
        "payment-required": x402RequirementPayload
      },
      bodyText: ""
    }
  });
  const x402Selection = selectPaymentAdapter({
    protocol: x402Protocol,
    requirement: x402Artifacts.requirement
  });
  assert.equal(x402Selection.adapter.id, "x402-charge");
  assert.equal(x402Selection.accept.scheme, "exact");

  const x402Template = buildCredentialTemplate({
    protocol: x402Protocol,
    challenge: null,
    requirement: x402Selection.requirement,
    accept: x402Selection.accept,
    adapter: x402Selection.adapter
  });
  assert.equal(x402Template.accept.scheme, "exact");
});

test("builds retry headers from family-specific adapter results", () => {
  const paymentauthHeaders = buildRetryRequestHeaders({
    protocol: {
      family: "paymentauth",
      requestHeader: "authorization"
    },
    adapterResult: {
      credential: {
        txHash: "tempo_mock_tx_001"
      }
    }
  });
  assert.match(paymentauthHeaders.authorization, /^Payment /);

  const x402Headers = buildRetryRequestHeaders({
    protocol: {
      family: "x402",
      requestHeader: "payment-signature"
    },
    adapterResult: {
      payload: {
        txHash: "0xabc123"
      }
    }
  });
  assert.ok(x402Headers["payment-signature"]);
});

test("runs a generic paid-http flow without owning settlement", async () => {
  const protocol = {
    family: "paymentauth",
    challengeHeader: "www-authenticate",
    requestHeader: "authorization",
    receiptHeader: "payment-receipt",
    requestedMethods: ["tempo"],
    adapter: {
      id: "tempo-charge"
    }
  };

  const result = await runPaidHttpFlow({
    request: {
      url: "https://agents.allium.so/api/v1/developer/wallet/transactions",
      method: "POST",
      body: { chain: "ethereum" }
    },
    protocol,
    probeResponse: {
      status: 402,
      ok: false,
      headers: {
        "content-type": "application/json",
        "www-authenticate": `Payment id="challenge_123", realm="agents.allium.so", method="tempo", intent="charge", request="${requestPayload}", opaque="${opaquePayload}"`,
        "payment-receipt": receiptPayload
      },
      bodyText: JSON.stringify({
        type: "https://paymentauth.org/errors/payment-required",
        title: "Payment required",
        status: 402,
        detail: "Choose a supported payment method and retry."
      })
    },
    adapterResult: {
      credential: {
        method: "tempo",
        txHash: "tempo_mock_tx_001"
      }
    },
    retryResponse: {
      status: 200,
      ok: true,
      headers: {
        "payment-receipt": receiptPayload
      },
      bodyText: JSON.stringify({
        ok: true
      })
    }
  });

  assert.equal(result.blocked, false);
  assert.equal(result.stage, "settled");
  assert.equal(result.protocol.selectedAdapter.id, "tempo-charge");
  assert.equal(result.protocol.receipt.reference, "tempo_tx_123");
});
