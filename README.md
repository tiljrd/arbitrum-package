# Arbitrum Kurtosis Package (arb-reth + Nitro)

This Kurtosis package launches a minimal Arbitrum stack using:
- L1 provided by the ethereum Kurtosis package (or a local anvil as a fallback during development)
- An arb-reth sequencer image (local build)
- Nitro components (arbnode, inbox-reader, batch-poster)

Status: scaffold; wiring will evolve as arb-reth implementation completes.

Using the ethereum package for L1
- This package is designed to use the ethereum package to spin up a minimal L1. The args/minimal.yaml describes basic ports/images. Wiring to the ethereum package is coming next as arb-reth Docker integration lands. For now, the scaffold uses a local anvil placeholder to allow fast iteration.

Build arb-reth Docker image locally
- From the reth repo root:
  - docker build -t arb-reth:local -f crates/arbitrum/bin/Dockerfile .
  - If you run into storage issues, run: docker system prune

Run the package
- Pull latest changes:
  - git pull
- Clean any old enclaves:
  - kurtosis clean -a
- Run:
  - kurtosis run --enclave test . --args-file args/minimal.yaml

View logs and endpoints
- L1 RPC: http://l1:8545 (placeholder; will be ethereum package’s L1 endpoint once wired)
- L2 RPC (arb-reth): http://arb-reth:8547
- Arbnode RPC: http://arbnode:8549
- Logs:
  - kurtosis service logs test l1
  - kurtosis service logs test arb-reth
  - kurtosis service logs test arbnode
  - kurtosis service logs test inbox-reader
  - kurtosis service logs test batch-poster

Next steps
- Replace the anvil placeholder with explicit wiring to the ethereum package (import-package pattern)
- Add startup scripts/args for arbnode, inbox-reader, and batch-poster to connect to L1 and arb-reth
- Validate eth_blockNumber increases on L2 and that L1 batch submissions appear in Nitro logs

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
