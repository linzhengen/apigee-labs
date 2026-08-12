# Apigee Labs

Google Cloud上に Apigee を中心とした API プラットフォームを構築するプロジェクト。
IAP 認証・Vertex AI 統合を含む、本番レベルのアーキテクチャを Terraform で管理。

## Architecture

```
                       ┌──────────────────────────────────────────────────────────┐
                       │                  Google Cloud Project                    │
                       │                                                          │
┌──────────┐  HTTPS    │  ┌──────────────┐                                        │
│          │ ────────► │  │ Global HTTPS │                                        │
│ Browser  │           │  │ LB + SSL     │                                        │
│          │ ◄──────── │  └──────┬───────┘                                        │
└──────────┘           │         │ URL Map                                        │
                       │    ┌────┴────┐                                           │
                       │    ▼         ▼                                           │
                       │ /ui/*     /api/*                                         │
                       │    │         │                                           │
                       │    ▼         ▼                                           │
                       │ ┌─────────────────┐  ┌─────────────────────────────┐     │
                       │ │ Backend Service │  │ Backend Service             │     │
                       │ │ (IAP enabled)   │  │ (IAP enabled)               │     │
                       │ │                 │  │                             │     │
                       │ │  ┌───────────┐  │  │  ┌───────────────────────┐  │     │
                       │ │  │Cloud Run  │  │  │  │ Apigee (PSC NEG)      │  │     │
                       │ │  │frontend   │  │  │  │                       │  │     │
                       │ │  │-service   │  │  │  │ vertexai-proxy        │  │     │
                       │ │  │(nginx)    │  │  │  │  JWT→email,SpikeArrest│  │     │
                       │ │  │           │  │  │  │  Quota,Token Tracking │──┼──► Vertex AI
                       │ │  │           │  │  │  │ backend-proxy (OIDC)  │──┼──► Cloud Run
                       │ │  │           │  │  │  │ {service}-proxy       │──┼──► Future
                       │ │  └───────────┘  │  │  └───────────────────────┘  │     │
                       │ └─────────────────┘  └─────────────────────────────┘     │
                       └──────────────────────────────────────────────────────────┘

  IAP は各 Backend Service に適用:
    ✅ Backend Service (Cloud Run frontend) — /ui/*
    ✅ Backend Service (Apigee PSC NEG)    — /api/*
    → 同一ドメインの IAP Cookie で全パスを保護
```

### Architecture (Mermaid)

```mermaid
graph TB
  subgraph Browser
    U[User / Browser]
  end

  subgraph Google["Google Identity"]
    GAUTH["Google OAuth 2.0"]
  end

  subgraph GCP["Google Cloud Project"]
    LB["Global HTTPS LB<br/>+ Managed SSL"]

    subgraph Auth["Authentication"]
      IAP["Identity-Aware Proxy (IAP)<br/>全 Backend Service に適用"]
    end

    subgraph URLMap["URL Map"]
      direction LR
      R_UI["/ui/{name}/*"]
      R_API["/api/*"]
    end

    subgraph Frontends["Frontend"]
      CR_FE["Cloud Run<br/>frontend-service<br/>(nginx + SPA)"]
    end

    subgraph ApigeeX["Apigee"]
      VP["vertexai-proxy<br/>/api/vertexai<br/>SpikeArrest + Quota + Token Tracking"]
      BP["backend-proxy<br/>/api/backend"]
      SP["...-proxy<br/>/api/{service}"]
    end

    subgraph Backends["Backend"]
      VAI["Vertex AI API<br/>Gemini 2.0 Flash / 1.5 Pro<br/>(Global / Regional)"]
      CR_BE["Cloud Run<br/>backend-service<br/>(FastAPI Agent)"]
      Future["Future Services<br/>MCP / gRPC / ..."]
    end

    subgraph VPC["VPC: main-vpc"]
      SUB_UI["run-ui<br/>10.0.1.0/26"]
      SUB_BE["run-backend<br/>10.0.1.64/26"]
      subgraph Peering["VPC Peering (10.100.0.0/22)"]
        AI["Apigee Instance"]
      end
    end
  end

  U -->|"1. HTTPS"| LB
  LB -->|"2. IAP 認証"| IAP
  IAP <-->|"OAuth Login"| GAUTH
  IAP -->|"3. JWT OK"| R_UI & R_API

  R_UI -->|Serverless NEG| CR_FE
  R_API -->|Hybrid NEG| AI
  AI --> VP & BP & SP
  VP -->|GoogleAccessToken| VAI
  BP -->|GoogleIDToken| CR_BE
  SP -.->|GoogleIDToken| Future
  CR_BE --- SUB_BE
```

### Request Flow

```mermaid
sequenceDiagram
  participant B as Browser
  participant LB as Global HTTPS LB
  participant IAP as IAP
  participant G as Google OAuth
  participant FE as Cloud Run Frontend
  participant AG as Apigee
  participant VAI as Vertex AI
  participant BE as Cloud Run Backend

  Note over B,BE: 1. 初回アクセス (IAP 認証)
  B->>LB: GET /ui/main/
  LB->>IAP: IAP 検証
  IAP-->>B: 302 → Google Login
  B->>G: OAuth Login
  G-->>B: Authorization Code
  B->>IAP: Code exchange
  IAP-->>B: Set IAP Cookie + 302 to /ui/main/

  Note over B,BE: 2. SPA 取得 (認証済み)
  B->>LB: GET /ui/main/ (with IAP Cookie)
  LB->>IAP: JWT 検証 OK
  IAP->>FE: GET /ui/main/
  FE-->>B: index.html (nginx)

  Note over B,BE: 3. Vertex AI API
  B->>LB: POST /api/vertexai/v1/models/gemini-2.5-flash:generateContent
  LB->>IAP: JWT 検証 OK (same domain cookie)
  IAP->>AG: PSC NEG
  AG->>AG: Decode IAP JWT (user email)
  AG->>AG: SpikeArrest + Quota check
  AG->>AG: Remove client auth + GoogleAccessToken
  AG->>VAI: POST /v1/projects/.../models/...
  VAI-->>AG: Response (with usageMetadata)
  AG->>AG: Extract token counts → Analytics
  AG-->>B: Response (with X-Quota-* headers)

  Note over B,BE: 4. Backend API
  B->>LB: POST /api/backend/v1/chat
  LB->>IAP: JWT 検証 OK
  IAP->>AG: PSC NEG
  AG->>AG: Remove client auth + GoogleIDToken
  AG->>BE: POST /v1/chat
  BE-->>B: Response
```

### Network

```mermaid
graph TB
  subgraph VPC["VPC: main-vpc"]
    subgraph Subnets["User-managed Subnets (10.0.0.0/16)"]
      S1["run-ui<br/>10.0.1.0/26<br/>(将来の動的 UI 用)"]
      S2["run-backend<br/>10.0.1.64/26<br/>(Cloud Run backend)"]
    end
    subgraph Peering["VPC Peering"]
      AP["Apigee Instance<br/>10.100.0.0/22 (ランタイム)"]
      TS["Apigee Troubleshooting<br/>10.100.4.0/28"]
    end
    S2 -->|Direct VPC Egress| AP
    FW["Firewall: allow-run-to-apigee<br/>EGRESS TCP:443 → 10.100.0.0/22, 10.100.4.0/28"]
  end
```

> **Note**: Apigee インスタンスには /22（ランタイム）と /28（トラブルシューティング）の 2 つの CIDR レンジが必要です。
> 両方をサービスネットワーキングの予約レンジに含め、VPC ピアリングで接続します。
> 詳細: [Apigee ネットワーキング オプション](https://docs.cloud.google.com/apigee/docs/api-platform/get-started/networking-options)

### CI/CD Pipeline

```mermaid
graph LR
  subgraph Frontend["Frontend Pipeline"]
    F1[Push to main<br/>apps/frontend/**] --> F2[Docker build<br/>nginx + SPA]
    F2 --> F3[Push to<br/>Artifact Registry]
    F3 --> F4[Deploy to<br/>Cloud Run]
  end

  subgraph Backend["Backend Pipeline"]
    B1[Push to main<br/>apps/backend/**] --> B2[Docker build<br/>Python + FastAPI]
    B2 --> B3[Push to<br/>Artifact Registry]
    B3 --> B4[Deploy to<br/>Cloud Run]
  end
```

## Project Structure

```
apigee-labs/
├── .terraform-version                    # tfenv: Terraform 1.15.8
├── .github/workflows/
│   ├── frontend-deploy.yml               # Docker → Artifact Registry → Cloud Run
│   └── backend-deploy.yml                # Docker → Artifact Registry → Cloud Run
│
├── apps/
│   ├── frontend/                         # React + Vite + TypeScript (Chat SPA)
│   │   ├── Dockerfile                    # Multi-stage: node build → nginx serve
│   │   ├── nginx.conf                    # SPA routing + security headers
│   │   ├── src/
│   │   │   ├── App.tsx                   # Chat UI + API バックエンド切替
│   │   │   ├── api.ts                    # Vertex AI / Backend Agent API
│   │   │   └── components/               # ChatMessage, ChatInput, BackendSelector
│   │   ├── vite.config.ts                # base: /ui/main/
│   │   └── package.json
│   │
│   └── backend/                          # Python FastAPI (Sample Agent)
│       ├── Dockerfile                    # Multi-stage build
│       └── main.py                       # /v1/health, /v1/chat
│
└── terraform/
    ├── envs/prod/                        # 本番環境
    │   ├── main.tf                       # 全モジュールのオーケストレーション
    │   ├── variables.tf
    │   └── outputs.tf
    │
    └── modules/
        ├── apigee/                       # Apigee Org/Instance/Env/Envgroup
        ├── apigee-vertexai-proxy/        # Vertex AI 専用プロキシ (/api/vertexai)
        ├── apigee-service-proxy/         # 汎用 Cloud Run プロキシ (/api/{service})
        ├── lb/                           # Global HTTPS LB + IAP + パスルーティング
        ├── github-wif/                    # GitHub Actions Workload Identity Federation
        └── iap/                          # IAP OAuth 設定 (gcloud CLI で作成した値を受け渡し)
```

## URL Design

| Path | Destination | IAP | Description |
|------|-------------|-----|-------------|
| `/` | → 302 `/ui/main/` | - | デフォルトリダイレクト |
| `/ui/main/*` | Cloud Run frontend | ✅ | メイン SPA (Chat) |
| `/ui/{name}/*` | Cloud Run | ✅ | 将来の追加フロントエンド |
| `/api/vertexai/v1/models/{model}:{action}` | Apigee → Vertex AI | ✅ | Gemini API (Global) |
| `/api/vertexai/v1/locations/{region}/models/{model}:{action}` | Apigee → Vertex AI | ✅ | Gemini API (Regional) |
| `/api/backend/v1/*` | Apigee → Cloud Run | ✅ | Backend Agent |
| `/api/{service}/v1/*` | Apigee → Cloud Run | ✅ | 将来のサービス追加 |

## Terraform Modules

### `apigee-service-proxy` (汎用)

`service_name` を指定するだけで Apigee プロキシを自動生成。

```hcl
module "backend_proxy" {
  source       = "../../modules/apigee-service-proxy"
  service_name = "backend"    # → BasePath: /api/backend, SA: apigee-backend-proxy-sa
  target_url   = module.backend.service_uri
  ...
}

# 将来: MCP サーバー
module "mcp_proxy" {
  source       = "../../modules/apigee-service-proxy"
  service_name = "mcp"        # → BasePath: /api/mcp
  target_url   = module.mcp_server.service_uri
  ...
}
```

### `lb` (複数フロントエンド + IAP 一括適用)

```hcl
ui_frontends = [
  { name = "main",  cloud_run_service_name = "frontend-service" },
  { name = "admin", cloud_run_service_name = "admin-service" },
]

# iap_config を指定すると全 Backend Service (UI + Apigee) に IAP 適用
iap_config = {
  oauth2_client_id     = var.iap_oauth_client_id
  oauth2_client_secret = var.iap_oauth_client_secret
}
iap_allowed_members = ["user:admin@example.com"]
```

## CI/CD

### Frontend / Backend 共通フロー

```
Push to main → Docker build → Artifact Registry push → Cloud Run deploy
```

- Frontend イメージ: `{region}-docker.pkg.dev/{project}/docker/frontend-service:{sha}`
- Backend イメージ: `{region}-docker.pkg.dev/{project}/docker/backend-service:{sha}`
- Artifact Registry リポジトリ: `docker` (共有)

## Setup

### Prerequisites

- Terraform >= 1.15 (`tfenv` で自動管理)
- Google Cloud プロジェクト (Apigee 有効化済み)
- ドメイン (DNS A レコード設定用)

### GitHub Actions Secrets (Environment: production)

| Secret | Description | 取得方法 |
|--------|-------------|----------|
| `GCP_PROJECT_ID` | Google Cloud プロジェクト ID | 手動設定 |
| `GCP_REGION` | リージョン | 手動設定 |
| `WORKLOAD_IDENTITY_PROVIDER` | WIF プロバイダー | `terraform output github_wif_provider` |
| `GCP_SERVICE_ACCOUNT` | CI/CD 用 SA | `terraform output github_wif_service_account` |

### IAP OAuth クライアントの作成

`google_iap_brand` / `google_iap_client` は 2026-03-19 に廃止されたため、
OAuth クライアントは gcloud CLI または Google Cloud Console で作成する。

```bash
# 1. OAuth 同意画面 (Brand) の作成
gcloud iap oauth-brands create \
  --application_title="Apigee Labs" \
  --support_email="YOUR_EMAIL"

# 2. OAuth クライアントの作成
gcloud iap oauth-clients create \
  "projects/YOUR_PROJECT_NUMBER/brands/YOUR_PROJECT_NUMBER" \
  --display_name="IAP OAuth Client"

# 3. 出力された client_id と client_secret を secrets.auto.tfvars に設定
#   iap_oauth_client_id     = "xxxx.apps.googleusercontent.com"
#   iap_oauth_client_secret = "GOCSPX-xxxx"
```

> **Note**: `YOUR_PROJECT_NUMBER` は `gcloud projects describe YOUR_PROJECT --format='value(projectNumber)'` で取得できます。

### 設定ファイルの準備

`terraform.tfvars` と `secrets.auto.tfvars` はコミットされないため、
example ファイルからコピーして作成します。

```bash
cd terraform/envs/prod

# 非機密の設定 (コミット対象)
cp terraform.tfvars.example terraform.tfvars

# 機密情報 (gitignore 対象、Terraform が自動読み込み)
cp secrets.auto.tfvars.example secrets.auto.tfvars
```

`terraform.tfvars` にはプロジェクト ID・ドメイン・`iap_allowed_members` などの
非機密の値を、`secrets.auto.tfvars` には IAP OAuth クライアントの
`iap_oauth_client_id` / `iap_oauth_client_secret` を設定します。

### Deploy

```bash
cd terraform/envs/prod
terraform init
terraform plan
terraform apply
```
