import test from "node:test";
import assert from "node:assert/strict";

import {
  buildSettlementAttempt,
  normalizeSettlementFailure,
  normalizeSettlementSuccess
} from "../src/index.js";

const requestPayload =
  "eyJhbW91bnQiOiIwLjA1IiwiYXNzZXQiOiJVU0QiLCJyZXNvdXJjZSI6Imh0dHBzOi8vYWdlbnRzLmFsbGl1bS5zby9hcGkvdjEvZGV2ZWxvcGVyL3dhbGxldC90cmFuc2FjdGlvbnMiLCJkZXNjcmlwdG9yIjoiYWxsaXVtIHdhbGxldCB0eCBoaXN0b3J5In0";
const opaquePayload =
  "eyJhdHRlbXB0IjoiZmlyc3QtcHJvYmUiLCJwcm92aWRlciI6ImFsbGl1bSJ9";

test("builds a settlement attempt for paymentauth executors", () => {
  const attempt = buildSettlementAttempt({
    request: {
      url: "https://agents.allium.so/api/v1/developer/wallet/transactions",
      method: "POST",
      headers: { "content-type": "application/json" },
      body: { chain: "ethereum" }
    },
    protocol: {
      family: "paymentauth"
    },
    selection: {
      adapter: { id: "tempo-charge" },
      challenge: {
        id: "challenge_123",
        realm: "agents.allium.so",
        method: "tempo",
        intent: "charge",
        request: { encoded: requestPayload },
        opaque: { encoded: opaquePayload }
      },
      requirement: null,
      accept: null
    },
    policy: {
      maxSpendUsd: "0.05"
    }
  });

  assert.equal(attempt.executorId, "tempo-charge");
  assert.equal(attempt.protocolFamily, "paymentauth");
  assert.equal(attempt.credentialTemplate.challenge.method, "tempo");
  assert.equal(attempt.policy.maxSpendUsd, "0.05");
});

test("normalizes settlement success into retry headers", () => {
  const success = normalizeSettlementSuccess({
    protocol: {
      family: "paymentauth",
      requestHeader: "authorization"
    },
    result: {
      credential: {
        txHash: "tempo_mock_tx_001"
      },
      paymentReceipt: {
        reference: "tempo_mock_tx_001"
      },
      metadata: {
        backend: "tempo-hash-local"
      }
    }
  });

  assert.equal(success.ok, true);
  assert.match(success.retryHeaders.authorization, /^Payment /);
  assert.equal(success.paymentReceipt.reference, "tempo_mock_tx_001");
  assert.equal(success.metadata.backend, "tempo-hash-local");
});

test("normalizes classified settlement failures", () => {
  const failure = normalizeSettlementFailure({
    retryable: true,
    category: "transport",
    message: "tempo RPC timed out",
    details: { attempt: 1 }
  });

  assert.deepEqual(failure, {
    ok: false,
    retryable: true,
    category: "transport",
    message: "tempo RPC timed out",
    details: { attempt: 1 }
  });
});
