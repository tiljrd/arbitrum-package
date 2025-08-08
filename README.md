# Arbitrum Kurtosis Package (arb-reth)

This Kurtosis package launches a local Arbitrum test network using:
- arb-reth as the L2 execution/sequencer client (tiljrd/reth)
- Nitro components (tiljrd/nitro) for inbox/rollup services and L1 posting
- An L1 dev chain (geth/anvil)
- Batch poster and inbox reader
- Optional DAS components depending on config

Status:
- Initial scaffolding is in place; services are placeholders that will be wired with real configs.
- The arb-reth Dockerfile clones tiljrd/arb-alloy into the builder image to satisfy path deps.

Prereqs:
- Docker
- Kurtosis CLI
- Make sure your local repos are up to date:
  - tiljrd/reth
  - tiljrd/nitro
  - tiljrd/nitro-testnode (reference for configs/ports)
  - tiljrd/optimism-package (structure reference)

Build the arb-reth image locally:
- From tiljrd/reth:
  docker build -t arb-reth:local -f crates/arbitrum/bin/Dockerfile .
  Note: Current build is blocked by a c-kzg native library version conflict inside the container (revm-precompile vs reth-primitives).
  Once c-kzg versions are aligned in the workspace, this build should succeed.

Run:
- Clean previous enclaves:
  kurtosis clean -a
- Execute with arguments:
  kurtosis run --enclave test . --args-file ./args/minimal.yaml

Verify (once services are fully wired):
- L2 RPC responds and eth_blockNumber increases.
- Nitro batch poster submits to L1 (logs).
- Retryable operations via ArbSys/ArbRetryableTx succeed.

Next steps (planned):
- Wire real service startup commands and env vars for arbnode, inbox-reader, and batch-poster
- Expose and connect endpoints across services
- Integrate contract deployment/init as needed
- Add more args-file presets beyond minimal
