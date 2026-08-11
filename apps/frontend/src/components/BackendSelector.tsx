import type { ApiBackend } from "../api";
import "./BackendSelector.css";

interface Props {
  value: ApiBackend;
  onChange: (backend: ApiBackend) => void;
}

const OPTIONS: { value: ApiBackend; label: string }[] = [
  { value: "vertexai", label: "Gemini (Vertex AI)" },
  { value: "backend", label: "Backend Agent" },
];

export function BackendSelector({ value, onChange }: Props) {
  return (
    <div className="backend-selector">
      {OPTIONS.map((opt) => (
        <button
          key={opt.value}
          className={`backend-option ${value === opt.value ? "active" : ""}`}
          onClick={() => onChange(opt.value)}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}
