# Imagen mínima para la tarea única storage-init.
FROM alpine:3.22
RUN apk add --no-cache curl jq
COPY --chmod=755 init.sh /usr/local/bin/garage-init
ENTRYPOINT ["/usr/local/bin/garage-init"]
