import type { Message } from "../api";
import "./ChatMessage.css";

export function ChatMessage({ message }: { message: Message }) {
  const isUser = message.role === "user";
  return (
    <div className={`message ${isUser ? "message-user" : "message-model"}`}>
      <div className="message-label">{isUser ? "You" : "Gemini"}</div>
      <div className="message-bubble">{message.text}</div>
    </div>
  );
}
