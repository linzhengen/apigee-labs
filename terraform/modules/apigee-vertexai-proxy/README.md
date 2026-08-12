# apigee-vertexai-proxy

Apigee X 経由で Vertex AI (Gemini 等) を呼び出すリバースプロキシモジュール。
IAP 認証済みユーザーの識別、レート制限、リクエスト数クォータ、LLM トークン使用量の収集を行う。

## アーキテクチャ

```
Client → LB (IAP) → Apigee X → Vertex AI
                       │
         ┌─────────────┼─────────────────┐
         │  Request     │  Response       │
         │  1. JWT decode (user email)    │
         │  2. SpikeArrest               │
         │  3. Quota (per user)          │
         │  4. Path → Vertex AI URL      │
         │             │                  │
         │             │  1. Extract token counts │
         │             │  2. DataCapture → Analytics │
         │             │  3. Quota headers │
         └─────────────┴─────────────────┘
```

## エンドポイント

```
POST /api/vertexai/v1/models/{model}:{action}
POST /api/vertexai/v1/locations/{region}/models/{model}:{action}
```

### 変換例

| 受信パス | 送信先 |
|---|---|
| `/api/vertexai/v1/models/gemini-2.5-flash:generateContent` | `https://aiplatform.googleapis.com/v1/projects/{project}/locations/global/publishers/google/models/gemini-2.5-flash:generateContent` |
| `/api/vertexai/v1/locations/asia-northeast1/models/gemini-2.5-flash:generateContent` | `https://asia-northeast1-aiplatform.googleapis.com/v1/projects/{project}/locations/asia-northeast1/publishers/google/models/gemini-2.5-flash:generateContent` |

## LLM 使用量管理

### レート制限・クォータ

| 機能 | ポリシー | デフォルト | 説明 |
|---|---|---|---|
| バースト防止 | `SA-SpikeArrest` | 10回/分 | ユーザーごとの短時間連続リクエスト防止 |
| リクエスト数上限 | `QU-PerUserQuota` | 100回/日 | ユーザーごとの日次リクエスト上限 (超過時 429) |

レスポンスヘッダーでクォータ残量を確認可能:

```
X-Quota-Limit: 100
X-Quota-Used: 42
X-Quota-Remaining: 58
```

### トークン使用量の収集

Vertex AI レスポンスの `usageMetadata` からトークン数を抽出し、Apigee Analytics に記録する。

| DataCollector | 型 | 内容 |
|---|---|---|
| `dc_user_email` | STRING | IAP ユーザーのメールアドレス |
| `dc_model_action` | STRING | 使用モデルとアクション (例: `gemini-2.5-flash:generateContent`) |
| `dc_target_region` | STRING | ターゲットリージョン (`global` / `asia-northeast1` 等) |
| `dc_prompt_token_count` | INTEGER | 入力トークン数 |
| `dc_candidates_token_count` | INTEGER | 出力トークン数 |
| `dc_total_token_count` | INTEGER | 合計トークン数 |

### 使用量の確認方法

**GCP コンソール:**

Apigee > Analytics > Custom Reports で、上記の DataCollector をディメンション・メトリクスとして指定。

**API:**

```bash
curl "https://apigee.googleapis.com/v1/organizations/{org}/environments/{env}/stats/dc_user_email" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -G \
  --data-urlencode "select=sum(dc_total_token_count)" \
  --data-urlencode "timeRange=08/01/2026 00:00~08/12/2026 23:59" \
  --data-urlencode "filter=(apiproxy eq 'vertexai-proxy')"
```

**Custom Report の作成 (API):**

```bash
curl -X POST "https://apigee.googleapis.com/v1/organizations/{org}/reports" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "Vertex AI Token Usage by User",
    "metrics": [
      {"name": "dc_total_token_count", "function": "sum"},
      {"name": "dc_prompt_token_count", "function": "sum"},
      {"name": "dc_candidates_token_count", "function": "sum"},
      {"name": "traffic", "function": "sum"}
    ],
    "dimensions": ["dc_user_email", "dc_model_action"],
    "filter": "(apiproxy eq '\''vertexai-proxy'\'')",
    "timeUnit": "day"
  }'
```

## Variables

| Name | Description | Type | Default |
|---|---|---|---|
| `project_id` | GCP プロジェクト ID | `string` | - |
| `project_number` | GCP プロジェクト番号 | `string` | - |
| `org_id` | Apigee Organization ID | `string` | - |
| `environment_name` | デプロイ先の Apigee 環境名 | `string` | - |
| `spike_arrest_rate` | ユーザーごとのレート制限 | `string` | `"10pm"` |
| `quota_limit` | ユーザーごとのリクエスト数上限 | `number` | `100` |
| `quota_interval` | クォータのインターバル数 | `number` | `1` |
| `quota_time_unit` | クォータの時間単位 | `string` | `"day"` |

## Usage

```hcl
module "vertexai_proxy" {
  source = "../../modules/apigee-vertexai-proxy"

  project_id       = var.project_id
  project_number   = data.google_project.project.number
  org_id           = module.apigee.org_id
  environment_name = "prod"

  # カスタマイズ例
  spike_arrest_rate = "30pm"
  quota_limit       = 200
  quota_interval    = 1
  quota_time_unit   = "day"
}
```

## ポリシー一覧

### Request (ProxyEndpoint PreFlow)

| 順序 | ポリシー | 説明 |
|---|---|---|
| 1 | `DJ-DecodeIapJwt` | IAP JWT からユーザー email を抽出 |
| 2 | `SA-SpikeArrest` | バースト防止 |
| 3 | `QU-PerUserQuota` | リクエスト数クォータ |
| 4 | `AM-RemoveClientAuth` | クライアント認証ヘッダー除去 |
| 5 | `EV-ExtractModelPath` | パスからモデル・リージョン抽出 |
| 6 | `RF-ModelNotFound` | モデル未指定時に 404 |
| 7 | `AM-ResolveRegion` | リージョン解決 (デフォルト: global) |
| 8 | `AM-SetRegionalHost` | リージョナルエンドポイントに切替 (条件付き) |

### Request (TargetEndpoint PreFlow)

| 順序 | ポリシー | 説明 |
|---|---|---|
| 1 | `AM-SetTargetPath` | `target.url` を Vertex AI フル URL に設定 |

### Response (TargetEndpoint PreFlow)

| 順序 | ポリシー | 説明 |
|---|---|---|
| 1 | `EV-ExtractTokenCounts` | レスポンスからトークン数を抽出 |
| 2 | `AM-CleanTokenCounts` | 抽出値の配列括弧を除去 |
| 3 | `SC-CollectUsageStats` | Analytics にカスタム統計を記録 |

### Response (ProxyEndpoint PreFlow)

| 順序 | ポリシー | 説明 |
|---|---|---|
| 1 | `AM-AddQuotaHeaders` | クォータ残量をレスポンスヘッダーに付与 |
