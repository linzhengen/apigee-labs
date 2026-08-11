export interface Message {
  role: "user" | "model";
  text: string;
}

export type ApiBackend = "vertexai" | "backend";

const VERTEXAI_MODEL = "gemini-2.0-flash";
const VERTEXAI_URL = `/api/vertexai/v1/models/${VERTEXAI_MODEL}:generateContent`;
const BACKEND_URL = "/api/backend/v1/chat";
const REQUEST_TIMEOUT_MS = 30_000;

export async function sendMessage(
  history: Message[],
  backend: ApiBackend,
): Promise<string> {
  if (backend === "vertexai") {
    return sendToVertexAI(history);
  }
  return sendToBackend(history);
}

async function fetchWithTimeout(
  url: string,
  options: RequestInit,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

function handleError(status: number): never {
  if (status === 401 || status === 403) {
    throw new Error("Authentication required. Please reload the page.");
  }
  if (status >= 500) {
    throw new Error("Server error. Please try again later.");
  }
  throw new Error(`Request failed (${status}).`);
}

async function sendToVertexAI(history: Message[]): Promise<string> {
  const contents = history.map((m) => ({
    role: m.role,
    parts: [{ text: m.text }],
  }));

  const res = await fetchWithTimeout(VERTEXAI_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ contents }),
  });

  if (!res.ok) handleError(res.status);

  const data = await res.json();
  return (
    data.candidates?.[0]?.content?.parts?.[0]?.text ?? "No response from model."
  );
}

async function sendToBackend(history: Message[]): Promise<string> {
  const lastMessage = history[history.length - 1];

  const res = await fetchWithTimeout(BACKEND_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: lastMessage.text }),
  });

  if (!res.ok) handleError(res.status);

  const data = await res.json();
  return data.reply ?? "No response from backend.";
}
