/**
 * The three arms of the model A/B (Ticket #285). The only variable per arm
 * is the GGUF together with its vendor's sampling recommendation. Revision
 * and SHA-256 are checked against the server while staging
 * (stage-gguf.mjs) and against the file before every A/B run.
 *
 * A and B carry exactly the sampling flags of the production start
 * (KomkiCli.Llama, Gemma 4 model card); as in production, min-p stays at
 * the llama-server default of 0.05. C carries the thinking-mode
 * recommendation of the Qwen3.8-27B model card (min_p 0, presence and
 * repetition penalties neutral).
 *
 * The server-build A/B (Ticket #320) keeps GGUF, drafter, sampling, flags
 * and seed fixed and varies only the llama-server binary: arms with a
 * `bin` override KOMKI_LLAMA_SERVER for their runs.
 */

import path from "node:path";

import { EXPERIMENTS_ROOT } from "../lib/config.mjs";
import { DEFAULT_LLAMA_SERVER } from "./staging-server.mjs";

const GEMMA_SAMPLING = { temp: 1.0, "top-p": 0.95, "top-k": 64 };

export const ARMS = {
  A: {
    label: "Pin: Gemma 4 26B-A4B-it UD-Q4_K_XL",
    repo: "unsloth/gemma-4-26B-A4B-it-GGUF",
    revision: "c099eb48e663fd284577b04978a94ffccb261841",
    file: "gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf",
    sha256: "ef728c8e0c337fd1067b947af006e38a9ef2419e56feced4fd29b4bf0636e30c",
    sampling: GEMMA_SAMPLING,
    port: 49611,
  },
  B: {
    label: "Gemma 4 26B-A4B-it QAT UD-Q4_K_XL",
    repo: "unsloth/gemma-4-26B-A4B-it-qat-GGUF",
    revision: "7b92b5b28818151e8669af2e45e88d6086f490dd",
    file: "gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf",
    sha256: "a7c5bc715f5ff8e99a3e8901ce7d2b42b402c669bf24f7c5250747633d0f5891",
    sampling: GEMMA_SAMPLING,
    port: 49612,
  },
  C: {
    label: "Qwen3.8-27B UD-Q4_K_XL",
    repo: "unsloth/Qwen3.8-27B-GGUF",
    revision: "4ca720788d1e01f1bff70c033e0d0028fd02e502",
    file: "Qwen3.8-27B-UD-Q4_K_XL.gguf",
    sha256: "3f227079003add2511437e5b1e94812e363385225bf6a9b47b0054a72bc8b01e",
    sampling: {
      temp: 1.0,
      "top-p": 0.95,
      "top-k": 20,
      "min-p": 0.0,
      "presence-penalty": 0.0,
      "repeat-penalty": 1.0,
    },
    port: 49613,
  },
};

/**
 * MTP drafters (multi-token prediction) shipped in the A and B repos at the
 * same revisions; staged under distinct names via stage-gguf.mjs --as.
 * Speculative decoding verifies every drafted token with the target model,
 * so it changes speed, not the output distribution.
 */
export const DRAFTS = {
  A: {
    repo: ARMS.A.repo,
    revision: ARMS.A.revision,
    file: "MTP/mtp-gemma-4-26B-A4B-it-Q8_0.gguf",
    as: "mtp-gemma-4-26B-A4B-it-Q8_0.gguf",
    sha256: "6326fb9f5e487aa8dcdd313a091e3c67724cb2a666ec3b7d2895b5b26d93ed1b",
  },
  B: {
    repo: ARMS.B.repo,
    revision: ARMS.B.revision,
    file: "MTP/mtp-gemma-4-26B-A4B-it-Q8_0.gguf",
    as: "mtp-gemma-4-26B-A4B-it-qat-Q8_0.gguf",
    sha256: "75f58e20c32281d1adc086c0569d53f147e8d81a7b8493cf4a73a028415f67af",
  },
};

const MTP_ARGS = ["--spec-type", "draft-mtp", "--spec-draft-n-max", "4"];

// Follow-up arms (labbook #285, section "Folgemessungen"): same GGUF and
// sampling as their base arm plus one extra server switch (A0M: both).
ARMS.A0 = {
  ...ARMS.A,
  label: "Pin without thinking (enable_thinking=false)",
  serverArgs: ["--chat-template-kwargs", '{"enable_thinking":false}'],
  port: 49614,
};
ARMS.AM = { ...ARMS.A, label: "Pin with MTP drafter", draft: DRAFTS.A, serverArgs: MTP_ARGS, port: 49615 };
ARMS.BM = { ...ARMS.B, label: "QAT with MTP drafter", draft: DRAFTS.B, serverArgs: MTP_ARGS, port: 49616 };
ARMS.A0M = {
  ...ARMS.A,
  label: "Pin without thinking, with MTP drafter",
  draft: DRAFTS.A,
  serverArgs: [...ARMS.A0.serverArgs, ...MTP_ARGS],
  port: 49618,
};

// Server-build arms (Ticket #320): the production configuration after #319
// (thinking off via --reasoning, MTP drafter). GGUF, drafter, sampling,
// flags and seed are identical for both arms — only the llama-server binary
// varies. V7 is the Homebrew pin (the live instance's binary), V8 the
// side-by-side v0.8.0 release build b11960, commit 8642541b2, extracted
// from the release asset llama-b11960-bin-macos-arm64.tar.gz
// (SHA-256 58e5a5e1d7c2bf66cedd9c29e0323f3e570660a70a1e2156d32eed08f4cc1e3c).
const PRODUCTION_ARGS = ["--reasoning", "off", ...MTP_ARGS];

ARMS.V7 = {
  ...ARMS.A,
  label: "Production config on llama-server 0.7.0 (build 11669, Homebrew pin)",
  draft: DRAFTS.A,
  serverArgs: PRODUCTION_ARGS,
  bin: DEFAULT_LLAMA_SERVER,
  port: 49619,
};
ARMS.V8 = {
  ...ARMS.V7,
  label: "Production config on llama-server 0.8.0 (build 11960, v0.8.0)",
  bin: path.join(EXPERIMENTS_ROOT, "downloads", "b11960", "llama-b11960", "llama-server"),
  port: 49620,
};

/**
 * Seed per round: round 0 is the warm-up, 1..n are measured runs; all arms
 * of a round share the seed. Each study gets its own base so that no run
 * repeats the seed of an earlier study.
 */
export function seedFor(round, base = 285_000) {
  return base + round;
}
