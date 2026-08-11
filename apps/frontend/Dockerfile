FROM node:22-slim AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Vite builds to dist/ with base /ui/main/
COPY --from=builder /app/dist /usr/share/nginx/html/ui/main
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
