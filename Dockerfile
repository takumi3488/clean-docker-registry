FROM alpine:latest
RUN apk add --no-cache \
  bash \
  curl \
  jq \
  ca-certificates && \
  update-ca-certificates
WORKDIR /app
COPY clean_registry.sh /app/clean_registry.sh
RUN chmod +x /app/clean_registry.sh
ENTRYPOINT ["/app/clean_registry.sh"]
