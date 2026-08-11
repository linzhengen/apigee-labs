#!/usr/bin/env bash
# ============================================================
# GitHub リポジトリのセットアップスクリプト
#
# 前提条件:
#   - gh CLI がインストール済み & ログイン済み (gh auth login)
#   - terraform apply 完了済み (output 値が必要)
#
# 使い方:
#   cd terraform/envs/prod
#   terraform output -json > /tmp/tf-output.json
#   cd ../../..
#   bash scripts/setup-github.sh
# ============================================================
set -euo pipefail

REPO="linzhengen/apigee-labs"
ENVIRONMENT="production"

# ============================================================
# 1. Terraform output から値を取得
# ============================================================
echo "==> Terraform output から値を取得..."

TF_OUTPUT="${TF_OUTPUT_FILE:-/tmp/tf-output.json}"
if [[ ! -f "$TF_OUTPUT" ]]; then
  echo "ERROR: $TF_OUTPUT が見つかりません"
  echo "  cd terraform/envs/prod && terraform output -json > $TF_OUTPUT"
  exit 1
fi

WIF_PROVIDER=$(jq -r '.github_wif_provider.value' "$TF_OUTPUT")
GCP_SA=$(jq -r '.github_wif_service_account.value' "$TF_OUTPUT")

if [[ -z "$WIF_PROVIDER" || "$WIF_PROVIDER" == "null" ]]; then
  echo "ERROR: github_wif_provider が取得できません。terraform apply を実行してください。"
  exit 1
fi

# 手動入力が必要な値
read -rp "GCP Project ID: " GCP_PROJECT_ID
read -rp "GCP Region [asia-northeast1]: " GCP_REGION
GCP_REGION="${GCP_REGION:-asia-northeast1}"

echo ""
echo "==> 設定値の確認:"
echo "  REPO:                        $REPO"
echo "  ENVIRONMENT:                 $ENVIRONMENT"
echo "  GCP_PROJECT_ID:              $GCP_PROJECT_ID"
echo "  GCP_REGION:                  $GCP_REGION"
echo "  WORKLOAD_IDENTITY_PROVIDER:  $WIF_PROVIDER"
echo "  GCP_SERVICE_ACCOUNT:         $GCP_SA"
echo ""
read -rp "続行しますか? (y/N): " CONFIRM
[[ "$CONFIRM" =~ ^[yY]$ ]] || { echo "中断しました。"; exit 0; }

# ============================================================
# 2. Environment "production" の作成
# ============================================================
echo ""
echo "==> Environment '$ENVIRONMENT' を作成..."

# Environment 作成 (既存なら更新)
gh api --method PUT "repos/$REPO/environments/$ENVIRONMENT" \
  --field "wait_timer=0" \
  --field "deployment_branch_policy[protected_branches]=false" \
  --field "deployment_branch_policy[custom_branch_policies]=true" \
  > /dev/null

echo "  Environment '$ENVIRONMENT' を作成しました。"

# ============================================================
# 3. Deployment branch policy: main のみ許可
# ============================================================
echo "==> Deployment branch policy を設定 (main only)..."

# 既存ポリシーを削除
EXISTING_POLICIES=$(gh api "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" --jq '.branch_policies[].id' 2>/dev/null || true)
for POLICY_ID in $EXISTING_POLICIES; do
  gh api --method DELETE "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies/$POLICY_ID" > /dev/null 2>&1 || true
done

# main ブランチのみ許可
gh api --method POST "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" \
  --field "name=main" \
  --field "type=branch" \
  > /dev/null

echo "  main ブランチのみデプロイ許可に設定しました。"

# ============================================================
# 4. Environment Secrets を設定
# ============================================================
echo "==> Environment secrets を設定..."

gh secret set GCP_PROJECT_ID          --repo "$REPO" --env "$ENVIRONMENT" --body "$GCP_PROJECT_ID"
gh secret set GCP_REGION              --repo "$REPO" --env "$ENVIRONMENT" --body "$GCP_REGION"
gh secret set WORKLOAD_IDENTITY_PROVIDER --repo "$REPO" --env "$ENVIRONMENT" --body "$WIF_PROVIDER"
gh secret set GCP_SERVICE_ACCOUNT     --repo "$REPO" --env "$ENVIRONMENT" --body "$GCP_SA"

echo "  4 個の secrets を設定しました。"

# ============================================================
# 5. Branch protection: main ブランチ
# ============================================================
echo "==> Branch protection を設定 (main)..."

gh api --method PUT "repos/$REPO/branches/main/protection" \
  --field "required_pull_request_reviews[required_approving_review_count]=1" \
  --field "required_pull_request_reviews[dismiss_stale_reviews]=true" \
  --field "enforce_admins=true" \
  --field "required_status_checks=null" \
  --field "restrictions=null" \
  > /dev/null 2>&1 || echo "  WARN: Branch protection の設定に失敗 (Free plan では一部制限あり)"

echo "  Branch protection を設定しました。"

# ============================================================
# 6. 確認
# ============================================================
echo ""
echo "==> セットアップ完了!"
echo ""
echo "確認コマンド:"
echo "  gh secret list --repo $REPO --env $ENVIRONMENT"
echo "  gh api repos/$REPO/environments/$ENVIRONMENT --jq '.protection_rules'"
echo ""
echo "次のステップ:"
echo "  1. git push origin main  (初回コミットをプッシュ)"
echo "  2. apps/frontend/** または apps/backend/** を変更して push"
echo "  3. GitHub Actions が自動デプロイを実行"
