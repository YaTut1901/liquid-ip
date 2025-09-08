#!/usr/bin/env bash
set -euo pipefail

# Build pure-args payload: (uint256 tokenId=1, string newUri)
# taskId encoded as arbitrary bytes ("task-1")
TASK_B64=$(printf 'task-1' | base64 -w0)
# Encode pure arguments without selector using constructor encoding
PAYLOAD_HEX=$(cast abi-encode "constructor(uint256,string)" 1 "ipfs://bafkreihlhqp6eltren2u7mwb2dh4iyjg3z7yw7vvwvjmvduvwgzehe5nqa")
PAYLOAD_B64=$(xxd -r -p <<< "${PAYLOAD_HEX#0x}" | base64 -w0)

# Call the performer
PROTO_DIR="$(go list -m -f '{{.Dir}}' github.com/Layr-Labs/protocol-apis@v1.18.0)/protos"
RESP_JSON=$(grpcurl -plaintext \
  -import-path "$PROTO_DIR" \
  -proto eigenlayer/hourglass/v1/performer/performer.proto \
  -d "{ \"taskId\": \"$TASK_B64\", \"payload\": \"$PAYLOAD_B64\" }" \
  localhost:8080 eigenlayer.hourglass.v1.performer.PerformerService/ExecuteTask)

echo "$RESP_JSON"

# Decode ABI result (uint256,bool,uint8) with Python to avoid cast signature issues
RESULT_B64=$(python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])' <<< "$RESP_JSON")
echo "Decoded result:"
RESULT_B64="$RESULT_B64" python3 - <<'PY'
import os, base64
b = base64.b64decode(os.environ['RESULT_B64'])
token_id = int.from_bytes(b[0:32], 'big')
valid = (b[63] == 1)
status = b[95]
print(f"tokenId={token_id}")
print(f"valid={str(valid).lower()}")
print(f"status={status}")
PY