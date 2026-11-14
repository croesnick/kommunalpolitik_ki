import { execFileSync } from "node:child_process";

export function tmux(socket, args) {
  return execFileSync("tmux", ["-L", socket, ...args], {
    encoding: "utf8",
    env: process.env,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

export function hasSession(socket, session) {
  try {
    tmux(socket, ["has-session", "-t", session]);
    return true;
  } catch {
    return false;
  }
}

export function startSession({ socket, session, cwd, command, width = 120, height = 40 }) {
  tmux(socket, [
    "new-session",
    "-d",
    "-s",
    session,
    "-x",
    String(width),
    "-y",
    String(height),
    "-c",
    cwd,
    command,
  ]);
}

export function capturePane(socket, session, history = 250) {
  return tmux(socket, [
    "capture-pane",
    "-p",
    "-J",
    "-t",
    session,
    "-S",
    String(-history),
  ]);
}

export function sendLiteral(socket, session, text) {
  tmux(socket, ["send-keys", "-t", session, "-l", text]);
}

export function sendKey(socket, session, key) {
  tmux(socket, ["send-keys", "-t", session, key]);
}

export function killSession(socket, session) {
  try {
    tmux(socket, ["kill-session", "-t", session]);
  } catch {}
}

export function killServer(socket) {
  try {
    tmux(socket, ["kill-server"]);
  } catch {}
}

export async function waitForPane({
  socket,
  session,
  predicate,
  timeoutMs = 15000,
  intervalMs = 100,
  history = 250,
}) {
  const deadline = Date.now() + timeoutMs;
  let last = "";
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      last = capturePane(socket, session, history);
      if (predicate(last)) return { ok: true, pane: last };
    } catch (error) {
      lastError = String(error);
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return { ok: false, pane: last, error: lastError };
}

export async function waitForSessionExit({ socket, session, timeoutMs = 5000 }) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (!hasSession(socket, session)) return true;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return false;
}

export function trimCapture(text, maxLines = 80) {
  return text
    .replace(/\r/g, "")
    .replace(/[ \t]+$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .split("\n")
    .slice(-maxLines)
    .join("\n");
}
