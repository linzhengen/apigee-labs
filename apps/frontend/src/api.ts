export interface Message {
  role: "user" | "model";
  text: string;
}

export type ApiBackend = "vertexai" | "backend";

const VERTEXAI_MODEL = "gemini-2.0-flash";
const VERTEXAI_URL = `/api/vertexai/v1/models/${VERTEXAI_MODEL}:generateContent`;
const BACKEND_URL = "/api/backend/v1/chat";

export async function sendMessage(
  history: Message[],
  backend: ApiBackend,
): Promise<string> {
  if (backend === "vertexai") {
    return sendToVertexAI(history);
  }
  return sendToBackend(history);
}

async function sendToVertexAI(history: Message[]): Promise<string> {
  const contents = history.map((m) => ({
    role: m.role,
    parts: [{ text: m.text }],
  }));

  const res = await fetch(VERTEXAI_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ contents }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`API error ${res.status}: ${err}`);
  }

  const data = await res.json();
  return (
    data.candidates?.[0]?.content?.parts?.[0]?.text ?? "No response from model."
  );
}

async function sendToBackend(history: Message[]): Promise<string> {
  const lastMessage = history[history.length - 1];

  const res = await fetch(BACKEND_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: lastMessage.text }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`API error ${res.status}: ${err}`);
  }

  const data = await res.json();
  return data.reply;
}
