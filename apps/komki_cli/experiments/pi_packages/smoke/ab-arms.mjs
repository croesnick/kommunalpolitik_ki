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
 */

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

/** Seed per round: round 0 is the warm-up, 1..n are measured runs; all arms of a round share the seed. */
export function seedFor(round) {
  return 285_000 + round;
}
