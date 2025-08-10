# Generate Preloaded Contracts Blob

This repository supports a fast "preloaded" mode that avoids re-deploying L1 contracts by preloading their code, storage, balance, and nonce into the L1 execution layer (via ethereum-package's network_params.additional_preloaded_contracts).

This section explains how to generate that blob from a previous successful full deployment using the EL debug APIs.

Prerequisites
- Run a full deployment once to obtain the deployment artifacts (contracts.json, deployed_chain_info.json, l2_chain_info.json).
- Ensure the EL RPC exposes the debug namespace (debug_dumpBlock). The ethereum-package supports this by default on devnets. If you see "Method not found" for debug_dumpBlock, re-run your EL with debug API enabled.
- On Linux, use http://172.17.0.1:<published-port> for EL RPC from inside containers.

Steps
1) Run a full deployment
- Example: kurtosis run --enclave arbitrum-full . --args-file args/full.yaml
- After success, download the arb-deploy-out files artifact containing:
  - contracts.json
  - deployed_chain_info.json
  - l2_chain_info.json

2) Generate the preloaded blob
- Use the Node.js tool under tools/ to fetch code, balances, nonces, and storage for all L1 contract addresses.
- The tool prefers debug_dumpBlock to collect account state including storage. It falls back to eth_getCode/eth_getBalance/eth_getTransactionCount if debug APIs are not available (storage will then be empty and likely insufficient).

Example:
- node tools/gen-preloaded.mjs --rpc http://172.17.0.1:41003 --contracts /path/to/contracts.json --block latest --out preloaded.json --encoding eth

Flags:
- --rpc: EL RPC URL (use host gateway 172.17.0.1 on Linux when called from containers)
- --contracts: Path to contracts.json from your previous run
- --block: Block tag or number (e.g., latest, 0x2a, 42). Choose a block at or after rollup deployment
- --out: Output file path for the generated JSON object
- --encoding: eth (e.g., "1.5ETH") or wei (hex Wei). The ethereum-package examples accept the "xETH" string format.

3) Embed into args and run preloaded
- Copy the contents of preloaded.json and paste it as a YAML string into deployment.preload.additional_preloaded_contracts.
- Also set deployment.preload.precomputed_artifacts with the three JSON artifacts from your full run.
- You can start from args/preloaded.generated.sample.yaml and replace the placeholders.

Run:
- kurtosis run --enclave arbitrum-preloaded . --args-file args/preloaded.generated.sample.yaml

Expected results
- The package will pass the additional_preloaded_contracts through to the ethereum-package.
- The deployer will run in skip mode if precomputed_artifacts are set, avoiding contract deployments.
- All L2 services should start and the rollup should be recognized with the same addresses as in your previous full run.

Troubleshooting
- If contracts appear missing or services fail to start, ensure debug_dumpBlock was available when generating the blob so that storage was captured.
- If calling from containers on Linux, ensure the RPC is reachable at http://172.17.0.1:<port>.
- If you need to include additional addresses beyond those in contracts.json, provide an --extra JSON file containing an array or object of addresses.


# Arbitrum Kurtosis Package

This package launches an Arbitrum One–equivalent local network with four deployment modes:
1) Deploy L1 and L2 with preloaded contracts for fast development
2) Deploy L1 and L2 from scratch (full deployment)
3) Deploy only L2 against an existing L1 that already has the contracts
4) Deploy only L2 against an existing L1 that doesn’t have the contracts yet (deploy contracts to external L1)

Core services: sequencer, inbox-reader, batch-poster, validator (optional), validation-node.
No AnyTrust/DAS and no Timeboost in this iteration.

## Prerequisites
- Kurtosis CLI installed

## Run
Always clean old enclaves first to avoid conflicts:
```
kurtosis clean -a
```

Examples:
- Mode 1 (preloaded, internal L1):
```
kurtosis run --enclave arbitrum-preloaded . --args-file args/preloaded.yaml
```
- Mode 2 (full, internal L1):
```
kurtosis run --enclave arbitrum-full . --args-file args/full.yaml
```
- Mode 3 (L2-only on external L1 with existing contracts; does not run ethereum-package):
```
kurtosis run --enclave arbitrum-l2-existing . --args-file args/external_existing.yaml
```
- Mode 4 (L2-only on external L1 and deploy contracts; does not run ethereum-package):
```
kurtosis run --enclave arbitrum-l2-deploy . --args-file args/external_deploy.yaml
```

## Args
See:
- args/preloaded.yaml
- args/full.yaml
- args/external_existing.yaml
- args/external_deploy.yaml

Top-level structure:
- deployment.mode: preloaded | full | external_existing | external_deploy
- For preloaded: deployment.preload.additional_preloaded_contracts is passed to the ethereum-package as network_params.additional_preloaded_contracts
- For external modes: deployment.external_l1.rpc_url and chain_id are required. In external_deploy also set private_key. In external_existing you must provide precomputed artifacts under external_l1.precomputed_artifacts (at least one of: contracts_json, deployed_chain_info_json, l2_chain_info_json).

Mode 1 uses ethereum-package’s additional_preloaded_contracts to preload code/balances/storage at mainnet addresses. The expected format is a JSON string:
```
'{
  "0x123463a4B065722E99115D6c222f267d9cABb524": {
    "balance": "1ETH",
    "code": "0x1234",
    "storage": {},
    "nonce": 0,
    "secretKey": "0x"
  }
}'
```

## Endpoints
- L1 RPC: printed as l1_rpc_url
- L2 RPC (sequencer): printed as l2_rpc_url
- Validation API (validation-node): printed as validation_api_url
- Validator RPC: printed as validator_rpc_url (when use_validator is true)

## Logs
```
kurtosis service logs <enclave> sequencer
kurtosis service logs <enclave> validator
kurtosis service logs <enclave> validation-node
```

## Generating preloaded contracts
To generate a preload blob:
1. Run a full deployment once (mode 2).
2. Enumerate the deployed contract addresses from /deploy/contracts.json and /deploy/deployed_chain_info.json.
3. For each address:
   - Query eth_getCode to get code
   - Query eth_getBalance and eth_getTransactionCount for balance/nonce
   - Use debug_dumpBlock or tracing to discover storage keys, then read them via eth_getStorageAt
4. Assemble a JSON matching ethereum-package’s additional_preloaded_contracts and place it in deployment.preload.additional_preloaded_contracts (as a single-quoted JSON string).

## Notes
- Modes 3 and 4 do not run the ethereum-package; they are L2-only against an external L1.
- When pointing containers to a host-running L1 RPC:
  - On Linux, use the Docker host gateway IP (often http://172.17.0.1:<mapped-port>) instead of 127.0.0.1, which resolves inside the container.
  - host.docker.internal is not always available on Linux; prefer the 172.17.0.1 form.
- AnyTrust/DAS and Timeboost are excluded.
- To try a different sequencer image, set l2.sequencer.image in the args file.
