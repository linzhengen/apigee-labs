FROM node:22-slim AS builder
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm run build

FROM nginx:1.27-alpine
# non-root ユーザーで実行するための準備
# - デフォルト設定を削除 (ポート80) し、カスタム設定 (ポート8080) のみ使用
# - pid ファイルの書き込み先を変更
RUN rm -f /etc/nginx/conf.d/default.conf && \
    sed -i 's|/var/run/nginx.pid|/tmp/nginx.pid|' /etc/nginx/nginx.conf && \
    chown -R nginx:nginx /var/cache/nginx /var/log/nginx /etc/nginx/conf.d /tmp
USER nginx
COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/app.conf
COPY --chown=nginx:nginx --from=builder /app/dist /usr/share/nginx/html/ui/main
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
