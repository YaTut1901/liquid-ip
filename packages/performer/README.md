# Liquid-IP Verifier Performer

A Go performer for Hourglass/Ponos Executor. It runs a gRPC server (PonosPerformer) that accepts tasks and returns ABI-encoded results to be submitted on-chain.

This package is under active development.

## Env
- PERFORMER_RPC_URL
- PERFORMER_ERC721_PATENT_REGISTRY_ADDRESS
- PERFORMER_IPFS_GATEWAY
- PERFORMER_SCHEMA_URI
- PERFORMER_PORT (default 8080)

## Build
```
go build ./cmd/performer
```

## Run
```
PERFORMER_RPC_URL=http://localhost:8545 \
PERFORMER_ERC721_PATENT_REGISTRY_ADDRESS=0x... \
PERFORMER_IPFS_GATEWAY=https://ipfs.io/ipfs \
PERFORMER_SCHEMA_URI=ipfs://... \
./performer
``` 