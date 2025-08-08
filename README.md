# Arbitrum Kurtosis Package (arb-reth)

This Kurtosis package launches a local Arbitrum test network using:
- arb-reth as the L2 execution/sequencer client (tiljrd/reth)
- Nitro components (tiljrd/nitro) for inbox/rollup services and L1 posting
- An L1 dev chain (geth/anvil)
- Batch poster and inbox reader
- Optional DAS components depending on config

Status:
- Initial scaffolding for the package. Integration with arb-reth and Nitro services will follow.
- The arb-reth Docker image is built from tiljrd/reth with crates/arbitrum/bin/Dockerfile.

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

Run:
- Clean previous enclaves:
  kurtosis clean -a
- Execute with arguments:
  kurtosis run --enclave test . --args-file ./args/minimal.yaml

Verify:
- L2 RPC responds and eth_blockNumber increases.
- Nitro batch poster submits to L1 (logs).
- Retryable operations via ArbSys/ArbRetryableTx succeed.

Notes:
- This package will be expanded to include:
  - networks: single-sequencer minimal, multi-node
  - configuration for L1 chain, contract deploy, and poster credentials
  - documentation on any Nitro changes needed to work with arb-reth
