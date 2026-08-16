# apigee-vertexai-proxy

Apigee 経由で Vertex AI (Gemini 等) を呼び出すリバースプロキシモジュール。
IAP 認証済みユーザーの識別、レート制限、リクエスト数クォータ、LLM トークン使用量の収集を行う。

## アーキテクチャ

```
Client → LB (IAP) → Apigee → Vertex AI
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

### 簡易パターン (フロントエンド fetch 用)

```
POST /api/vertexai/v1/models/{model}:{action}
POST /api/vertexai/v1/locations/{region}/models/{model}:{action}
```

### SDK パターン (google-genai SDK 用)

```
POST /api/vertexai/v1/projects/{project}/locations/{region}/publishers/google/models/{model}:{action}
```

### 変換例

| 受信パス | 送信先 |
|---|---|
| `/api/vertexai/v1/models/gemini-2.5-flash:generateContent` | `https://aiplatform.googleapis.com/v1/projects/{project}/locations/global/publishers/google/models/gemini-2.5-flash:generateContent` |
| `/api/vertexai/v1/locations/asia-northeast1/models/gemini-2.5-flash:generateContent` | `https://asia-northeast1-aiplatform.googleapis.com/v1/projects/{project}/locations/asia-northeast1/publishers/google/models/gemini-2.5-flash:generateContent` |
| `/api/vertexai/v1/projects/*/locations/us-central1/publishers/google/models/gemini-2.5-flash:generateContent` | `https://us-central1-aiplatform.googleapis.com/v1/projects/{terraform_project_id}/locations/us-central1/publishers/google/models/gemini-2.5-flash:generateContent` (project は Terraform 値に強制) |

### Python SDK (google-genai) での利用例

IAP で保護されたエンドポイントにアクセスするには、IAP クライアント ID を audience に指定した ID トークンが必要です。

`google-genai` SDK を Apigee プロキシ経由で使う場合、以下の SDK 制約に対応する必要があります:

1. SDK はデフォルトで `api_version='v1beta1'` を付与する → `api_version='v1'` で上書き
2. `project`/`location` を指定すると SDK が Authorization ヘッダーを ADC アクセストークンで上書きしてしまう → `project`/`location` は指定しない
3. `project`/`location` 未指定 + カスタム `base_url` では SDK がパスを構築しない → ダミーの `api_key` で回避

以下は 実行コード (response 行を除く) 例です:

```python
from google import genai
from google.oauth2 import service_account
from google.auth.transport.requests import Request

IAP_CLIENT_ID = "YOUR_IAP_CLIENT_ID.apps.googleusercontent.com"
SA_KEY_PATH = "path/to/your-service-account-key.json"

def get_iap_token(iap_client_id, sa_key_path):
    """サービスアカウントの鍵から IAP 用 ID トークンを生成する。"""
    credentials = service_account.IDTokenCredentials.from_service_account_file(
        sa_key_path,
        target_audience=iap_client_id,
    )
    credentials.refresh(Request())
    return credentials.token

iap_token = get_iap_token(IAP_CLIENT_ID, SA_KEY_PATH)

# api_key にダミー値を渡すことで、SDK がカスタム base_url に対して
# パスを正しく構築し、かつ ADC アクセストークンで Authorization ヘッダーを
# 上書きしないようにする
client = genai.Client(
    vertexai=True,
    api_key='dummy-api-key',  # ダミー: パス構築の有効化 + Authorization 上書き防止
    http_options={
        'base_url': 'https://YOUR_DOMAIN/api/vertexai/',
        'api_version': 'v1',
        'headers': {'Authorization': f'Bearer {iap_token}'},
    },
)
```

> **Note**: Cloud Run / GCE 上ではメタデータサーバーから自動取得する方法もある。`gcloud` CLI が使えない環境では `requests` でメタデータサーバーに問い合わせる。

`model` の指定方法は 3 通りある。SDK 内部で `t_model()` → メソッド suffix (`:generateContent`) 付与 → `api_version` 前置 の変換を経て、以下のリクエストパスがプロキシに届く。

プロキシの `EV-ExtractModelPath`  (`#` はパターン番号) は 4 つのパターンで `modelAction` と `targetRegion` を抽出し、`AM-SetTargetPath` が Terraform の `project_id` を使って Vertex AI バックエンド URL を組み立てる。

```
EV-ExtractModelPath のマッチングパターン (proxy.pathsuffix に対するマッチ):

  #1  /{apiVersion}/projects/{sdkProject}/locations/{targetRegion}/publishers/{sdkPublisher}/models/{modelAction}
  #2  /{apiVersion}/publishers/{sdkPublisher}/models/{modelAction}
  #3  /{apiVersion}/locations/{targetRegion}/models/{modelAction}
  #4  /{apiVersion}/models/{modelAction}
```

| # | model 値 | SDK が生成するリクエストパス | マッチする EV パターン | targetRegion | バックエンドリージョン |
|---|----------|---------------------------|---------------------|-------------|---------------------|
| 1 | `'gemini-2.5-flash'` | `v1/publishers/google/models/gemini-2.5-flash:generateContent` | `#2` (publishers) | **(なし)** | `global` |
| 2 | `'publishers/google/models/gemini-2.5-flash'` | `v1/publishers/google/models/gemini-2.5-flash:generateContent` | `#2` (publishers) | **(なし)** | `global` |
| 3 | `'projects/{p}/locations/{r}/publishers/google/models/gemini-2.5-flash'` | `v1/projects/{p}/locations/{r}/publishers/google/models/gemini-2.5-flash:generateContent` | `#1` (SDK フルパス) | `{r}` | `{r}` |

- **パターン 1, 2**: リクエストパスにリージョン情報がないため、`AM-ResolveRegion` によって `targetRegion` → `global` にフォールバックされる。グローバルエンドポイント (`aiplatform.googleapis.com`) にルーティングされる
- **パターン 3**: リクエストパスからリージョンが抽出され、`AM-SetRegionalHost` によってリージョナルエンドポイント (`{region}-aiplatform.googleapis.com`) にルーティングされる。リージョンを指定したい場合はこのパターンを使う
- **project は常に Terraform 値**: パターン 3 で `{sdkProject}` は抽出されるが、`AM-SetTargetPath` は常に Terraform の `project_id` を使用するため、SDK 側のプロジェクト指定は無視される

```python
# パターン 1: 短縮名 (推奨)
response = client.models.generate_content(
    model='gemini-2.5-flash',
    contents='Hello',
)

# パターン 2: publishers パス
response = client.models.generate_content(
    model='publishers/google/models/gemini-2.5-flash',
    contents='Hello',
)

# パターン 3: フルパス (project/location はプロキシ側の Terraform 値で上書き)
response = client.models.generate_content(
    model='projects/my-project/locations/asia-northeast1/publishers/google/models/gemini-2.5-flash',
    contents='Hello',
)

print(response.text)
```

> **仕組み**: `model='gemini-2.5-flash'` は SDK の `t_model()` によって `publishers/google/models/gemini-2.5-flash` に展開され、`_build_request()` 内で `api_version='v1'` が前置される。最終的なリクエスト URL は `POST /api/vertexai/v1/publishers/google/models/gemini-2.5-flash:generateContent` となり、プロキシの `EV-ExtractModelPath` でパースされた後、`AM-SetTargetPath` が Terraform の `project_id` を使って完全な Vertex AI エンドポイント URL に組み立てる。

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
| 1 | `AM-SetTargetPath` | `target.url` を Vertex AI フル URL に設定 (project_id は常に Terraform 値を使用) |

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
