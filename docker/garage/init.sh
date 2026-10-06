#!/bin/sh
# Prepara Garage para desarrollo: asigna el layout del nodo, importa la clave
# de acceso, crea el bucket y sus reglas CORS. Es idempotente.
set -eu

ADMIN="http://${GARAGE_HOST:-storage}:3903"
AUTH="Authorization: Bearer ${GARAGE_ADMIN_TOKEN}"

api() {
  method="$1"; path="$2"; shift 2
  curl -fsS -X "$method" -H "$AUTH" -H "Content-Type: application/json" "$ADMIN$path" "$@"
}

echo "Esperando a Garage…"
until curl -fsS -o /dev/null -H "$AUTH" "$ADMIN/v2/GetClusterStatus"; do sleep 1; done

# 1. Layout: un único nodo con capacidad de 10 GB.
layout_version=$(api GET /v2/GetClusterLayout | jq -r '.version')
if [ "$layout_version" = "0" ]; then
  node_id=$(api GET /v2/GetClusterStatus | jq -r '.nodes[0].id')
  api POST /v2/UpdateClusterLayout \
    -d "{\"roles\":[{\"id\":\"$node_id\",\"zone\":\"dc1\",\"capacity\":10000000000,\"tags\":[\"dev\"]}]}" >/dev/null
  api POST /v2/ApplyClusterLayout -d '{"version":1}' >/dev/null
  echo "Layout aplicado al nodo $node_id."
fi

# 2. Clave de acceso fija, para que la configuración de la app no cambie.
if ! api GET "/v2/GetKeyInfo?id=${S3_ACCESS_KEY_ID}" >/dev/null 2>&1; then
  api POST /v2/ImportKey \
    -d "{\"accessKeyId\":\"$S3_ACCESS_KEY_ID\",\"secretAccessKey\":\"$S3_SECRET_ACCESS_KEY\",\"name\":\"amauta-dev\"}" >/dev/null
  echo "Clave $S3_ACCESS_KEY_ID importada."
fi

# 3. Bucket con permisos para la clave.
if bucket=$(api GET "/v2/GetBucketInfo?globalAlias=${S3_BUCKET}" 2>/dev/null); then
  bucket_id=$(echo "$bucket" | jq -r '.id')
else
  bucket_id=$(api POST /v2/CreateBucket -d "{\"globalAlias\":\"$S3_BUCKET\"}" | jq -r '.id')
  echo "Bucket $S3_BUCKET creado."
fi
api POST /v2/AllowBucketKey \
  -d "{\"bucketId\":\"$bucket_id\",\"accessKeyId\":\"$S3_ACCESS_KEY_ID\",\"permissions\":{\"read\":true,\"write\":true,\"owner\":true}}" >/dev/null

# 4. CORS para la subida directa desde el navegador.
api POST "/v2/UpdateBucket?id=$bucket_id" -d "{
  \"corsRules\": [{
    \"AllowedOrigin\": [\"${CORS_ORIGIN:-http://localhost:4000}\"],
    \"AllowedMethod\": [\"GET\", \"HEAD\", \"PUT\", \"POST\"],
    \"AllowedHeader\": [\"*\"],
    \"ExposeHeader\": [\"ETag\"],
    \"MaxAgeSeconds\": 3600
  }]
}" >/dev/null

echo "Garage listo: bucket $S3_BUCKET."
