FROM node:8.9.1 AS build
ADD . /app
WORKDIR /app

FROM gcr.io/distroless/nodejs
COPY --from=build /app /app
WORKDIR /app
CMD ["under-construction.js"]
