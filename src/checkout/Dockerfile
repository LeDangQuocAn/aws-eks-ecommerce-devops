FROM node:20-alpine AS build
WORKDIR /usr/src/app
COPY --chown=node:node package*.json ./
COPY --chown=node:node . .
RUN yarn install --frozen-lockfile
RUN yarn build
USER node

FROM node:20-alpine AS runtime

WORKDIR /app
USER node

COPY --chown=node:node --from=build /usr/src/app/node_modules ./node_modules
COPY --chown=node:node --from=build /usr/src/app/dist ./dist

EXPOSE 8080

ENTRYPOINT [ "node", "dist/main.js" ]