# usage-pipeline

Apigee が送信した利用ログ (メッセージ・トークン数) を **Pub/Sub → Cloud Run Functions → BigQuery**
の非同期パイプラインで記録するモジュール。

API レスポンスのフロー内で DB 書き込みや解析を行わないため、
ユーザーへのレスポンスタイムを悪化させずにログ保存・トークン集計を実現する。

## アーキテクチャ

```
[Client]
   │
   ▼
┌────────────────────────────────────────────────────────┐
│ Apigee vertexai-proxy                                  │
│  1. Request  : Vertex AI へ転送                        │
│  2. Target   : Vertex AI (Gemini API) 呼び出し         │
│  3. Response : クライアントへ返却 & Pub/Sub へ非同期送信 │
└──────────────────────────┬─────────────────────────────┘
                           │ ServiceCallout (fire-and-forget)
                           ▼
                 ┌──────────────────┐
                 │  Pub/Sub Topic   │  apigee-usage-logs
                 └─────────┬────────┘
                           │ Eventarc Trigger
                           ▼
             ┌───────────────────────────┐
             │ Cloud Run Functions       │  usage-logger (Python 3.12)
             │ (メッセージ解析 & 書き込み) │
             └─────────────┬─────────────┘
                           ▼
                 ┌──────────────────┐
                 │ BigQuery         │  apigee_usage.vertexai_usage_logs
                 └──────────────────┘
```

送信側 (Apigee のポリシー構成) は `apigee-vertexai-proxy` モジュールの README を参照。

## 作成されるリソース

| リソース | 名前 (デフォルト) | 説明 |
|---|---|---|
| Pub/Sub トピック | `apigee-usage-logs` | Apigee からの利用ログを受信 |
| BigQuery データセット | `apigee_usage` | 利用ログの保存先 |
| BigQuery テーブル | `vertexai_usage_logs` | `timestamp` で日次パーティション、`user_id` / `model` でクラスタリング |
| Cloud Run Functions | `usage-logger` | Pub/Sub トリガーで BigQuery へ書き込み |
| サービスアカウント | `usage-logger-sa` | 関数のビルド & 実行 |
| GCS バケット | `{project_id}-usage-logger-source` | 関数ソースの保管 (30 日で自動削除) |

## テーブルスキーマ

`schema.json` を参照。1 リクエスト = 1 行で、主なカラムは以下:

| カラム | 型 | 内容 |
|---|---|---|
| `transaction_id` | STRING | Apigee `messageid` |
| `timestamp` | TIMESTAMP | リクエスト時刻 (パーティションキー) |
| `user_id` | STRING | IAP ユーザーのメールアドレス |
| `model` / `action` | STRING | `gemini-2.5-flash` / `generateContent` |
| `region` | STRING | `global` またはリージョン名 |
| `status_code` / `latency_ms` | INTEGER | レスポンスステータスと所要時間 |
| `prompt_token_count` / `candidates_token_count` / `total_token_count` | INTEGER | トークン使用量 |
| `request_payload` / `response_payload` | STRING | プロンプト・生成文 (無効化可能) |
| `ingested_at` | TIMESTAMP | BigQuery への書き込み時刻 |

## 配信保証

- 関数は BigQuery への書き込みに失敗すると例外を送出し、Pub/Sub が再配信する
  (`retry_policy = RETRY_POLICY_RETRY`)。
- 再配信による重複を避けるため、`insertId` に Pub/Sub の `messageId` を使用する。
- デコードできない・JSON オブジェクトでないメッセージは再試行しても成功しないため、
  ログを残して ack する。

## 集計クエリ例

```sql
-- ユーザー別・モデル別の日次トークン使用量
SELECT
  DATE(timestamp) AS day,
  user_id,
  model,
  COUNT(*) AS requests,
  SUM(prompt_token_count) AS prompt_tokens,
  SUM(candidates_token_count) AS output_tokens,
  SUM(total_token_count) AS total_tokens
FROM `PROJECT.apigee_usage.vertexai_usage_logs`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY day, user_id, model
ORDER BY day DESC, total_tokens DESC;
```

## Variables

| Name | Description | Type | Default |
|---|---|---|---|
| `project_id` | GCP プロジェクト ID | `string` | - |
| `region` | 関数 / Eventarc トリガーのリージョン | `string` | - |
| `function_source_dir` | 関数ソースのディレクトリパス | `string` | - |
| `topic_name` | Pub/Sub トピック名 | `string` | `"apigee-usage-logs"` |
| `message_retention_duration` | メッセージ保持期間 | `string` | `"86400s"` |
| `publisher_members` | publish を許可する IAM メンバー | `list(string)` | `[]` |
| `dataset_id` | BigQuery データセット ID | `string` | `"apigee_usage"` |
| `table_id` | BigQuery テーブル ID | `string` | `"vertexai_usage_logs"` |
| `bigquery_location` | データセットのロケーション | `string` | `"asia-northeast1"` |
| `partition_expiration_days` | パーティション保持日数 (0 で無期限) | `number` | `365` |
| `delete_contents_on_destroy` | destroy 時にテーブルも削除するか | `bool` | `false` |
| `function_name` | 関数名 | `string` | `"usage-logger"` |
| `max_instance_count` | 関数の最大インスタンス数 | `number` | `10` |

## Usage

```hcl
module "usage_pipeline" {
  source = "../../modules/usage-pipeline"

  project_id          = var.project_id
  region              = var.regions[0]
  topic_name          = local.usage_log_topic
  bigquery_location   = var.regions[0]
  function_source_dir = "${path.module}/../../../apps/usage-logger"

  publisher_members = [
    "serviceAccount:${module.vertexai_proxy.service_account_email}",
  ]
}
```

> **Note**: トピック名は `apigee-vertexai-proxy` モジュールの `usage_log_topic` と一致させる必要がある。
> 双方が同じトピックを参照するため、モジュール間の循環依存を避けてルート側の `locals` で定義する。

## 後続処理の追加

Pub/Sub を挟んでいるため、トークン記録以外の非同期処理も追加できる:

- 監査ログの長期保存 (別サブスクリプション → GCS)
- 非同期でのコンテンツ評価 (別の Cloud Run Functions)
- リアルタイム分析 (Dataflow / BigQuery サブスクリプション)

トピックに新しいサブスクリプションを追加するだけでよく、Apigee 側の変更は不要。
