import { readFile } from "node:fs/promises";

export async function parseSessionFile(file) {
  const raw = await readFile(file, "utf8");
  const parseErrors = [];
  const entries = [];
  for (const [i, line] of raw.split("\n").entries()) {
    if (!line.trim()) continue;
    try {
      entries.push(JSON.parse(line));
    } catch (error) {
      parseErrors.push({ line: i + 1, error: String(error), text: line.slice(0, 200) });
    }
  }

  const header = entries.find((e) => e.type === "session") ?? null;
  const messages = entries.filter((e) => e.type === "message").map((e) => e.message);

  const toolCalls = [];
  for (const entry of entries) {
    if (entry.type !== "message" || entry.message?.role !== "assistant") continue;
    const content = entry.message.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block?.type !== "toolCall") continue;
      toolCalls.push({
        entryId: entry.id,
        id: block.id,
        name: block.name,
        arguments: block.arguments,
      });
    }
  }

  const toolResults = entries
    .filter((e) => e.type === "message" && e.message?.role === "toolResult")
    .map((e) => ({
      entryId: e.id,
      toolCallId: e.message.toolCallId,
      toolName: e.message.toolName,
      content: e.message.content,
      isError: e.message.isError,
      text: contentText(e.message.content),
    }));

  const customEntries = entries
    .filter((e) => e.type === "custom")
    .map((e) => ({
      entryId: e.id,
      customType: e.customType,
      data: e.data,
      timestamp: e.timestamp,
    }));

  const compactions = entries.filter((e) => e.type === "compaction");
  const branchSummaries = entries.filter((e) => e.type === "branch_summary");
  const customMessages = entries.filter((e) => e.type === "custom_message");

  return {
    file,
    header,
    entries,
    messages,
    toolCalls,
    toolResults,
    customEntries,
    compactions,
    branchSummaries,
    customMessages,
    parseErrors,
    raw,
  };
}

export function contentText(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((block) => block?.type === "text")
    .map((block) => block.text ?? "")
    .join("\n");
}

export function findToolCall(session, name, predicate = () => true) {
  return session.toolCalls.find((call) => call.name === name && predicate(call));
}

export function findToolResult(session, nameOrId) {
  return session.toolResults.find(
    (result) =>
      result.toolName === nameOrId ||
      result.toolCallId === nameOrId ||
      result.entryId === nameOrId,
  );
}

export function resultsFor(session, call) {
  return session.toolResults.filter((r) => r.toolCallId === call.id);
}

export function customEntriesOfType(session, customType) {
  return session.customEntries.filter((entry) => entry.customType === customType);
}

export function eventTypes(events) {
  return events.map((event) => event.type);
}

export function findEvent(events, type) {
  return events.find((event) => event.type === type);
}

export function findEvents(events, type) {
  return events.filter((event) => event.type === type);
}
