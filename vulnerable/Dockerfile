FROM node:20-alpine

WORKDIR /app

# Instala dependência nativa do better-sqlite3
RUN apk add --no-cache python3 make g++

COPY package.json .
RUN npm install

COPY . .

EXPOSE 3000

CMD ["node", "server.js"]
