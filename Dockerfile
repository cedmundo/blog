# Build
FROM alpine:latest AS build
RUN apk add --update hugo git bash sed
WORKDIR /workspace
COPY . .
RUN hugo

# Serve
FROM nginx:1.25-alpine
WORKDIR /usr/share/nginx/html
COPY --from=build /workspace/public .
# Expose port 80
EXPOSE 80/tcp
