FROM node:24-bookworm-slim
WORKDIR /opt/rmcs/server
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev
COPY server/schema.sql .
COPY server/src ./src
COPY app/build/web /opt/rmcs/web
ENV HOST=0.0.0.0 PORT=8080 WEB_ROOT=/opt/rmcs/web NODE_ENV=production
USER node
EXPOSE 8080
CMD ["node", "src/server.ts"]
