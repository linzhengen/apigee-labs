import { useState, useRef, useEffect } from "react";
import { ChatMessage } from "./components/ChatMessage";
import { ChatInput } from "./components/ChatInput";
import { BackendSelector } from "./components/BackendSelector";
import { sendMessage, type Message, type ApiBackend } from "./api";
import "./App.css";

export function App() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(false);
  const [backend, setBackend] = useState<ApiBackend>("vertexai");
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const handleSend = async (text: string) => {
    const userMsg: Message = { role: "user", text };
    setMessages((prev) => [...prev, userMsg]);
    setLoading(true);

    try {
      const reply = await sendMessage([...messages, userMsg], backend);
      setMessages((prev) => [...prev, { role: "model", text: reply }]);
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : "An error occurred";
      setMessages((prev) => [
        ...prev,
        { role: "model", text: `Error: ${errMsg}` },
      ]);
    } finally {
      setLoading(false);
    }
  };

  const handleBackendChange = (b: ApiBackend) => {
    setBackend(b);
    setMessages([]);
  };

  const emptyText =
    backend === "vertexai"
      ? "Send a message to start chatting with Gemini."
      : "Send a message to the backend agent.";

  return (
    <div className="chat-container">
      <header className="chat-header">
        <h1>Apigee Labs Chat</h1>
        <BackendSelector value={backend} onChange={handleBackendChange} />
      </header>
      <main className="chat-messages">
        {messages.length === 0 && (
          <div className="chat-empty">{emptyText}</div>
        )}
        {messages.map((msg, i) => (
          <ChatMessage key={i} message={msg} />
        ))}
        {loading && <ChatMessage message={{ role: "model", text: "..." }} />}
        <div ref={bottomRef} />
      </main>
      <ChatInput onSend={handleSend} disabled={loading} />
    </div>
  );
}
