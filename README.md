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

## Genesis-based Preloaded Boot (no L1 logs)
When using preloaded mode, you can bypass L1 init log ingestion by booting Nitro from a genesis info-file.

Steps:
1) After a successful full run (mode 2), collect:
   - /deploy/deployed_chain_info.json
   - /deploy/l2_chain_config.json (or use the template defaults)
2) Generate a genesis info-file with has-genesis-state: true:
   - Makefile:
     - make gen-genesis-info DEPLOYED=/path/deployed_chain_info.json L2CONFIG=/path/l2_chain_config.json OUT=/path/l2_chain_info.genesis.json
   - Or directly:
     - node tools/gen-genesis-info.mjs --deployed /path/deployed_chain_info.json --l2config /path/l2_chain_config.json --out /path/l2_chain_info.genesis.json
3) Generate the preloaded contracts blob (accounts state) if you haven’t already:
   - Makefile:
     - make gen-preloaded RPC=http://172.17.0.1:<port> CONTRACTS=/path/contracts.json BLOCK=latest OUT=/path/preloaded.json ENCODING=eth
   - Or directly:
     - node tools/gen-preloaded.mjs --rpc http://172.17.0.1:<port> --contracts /path/contracts.json --block latest --out /path/preloaded.json --encoding eth
4) Update your preloaded args:
   - deployment.preload.additional_preloaded_contracts: embed contents of preloaded.json
   - deployment.preload.precomputed_artifacts: include the three artifacts from the full run (contracts.json, deployed_chain_info.json, l2_chain_info.json)
   - l2.info_file_path: "/deploy/l2_chain_info.genesis.json"
     - The package will mount your genesis info-file at /deploy/l2_chain_info.genesis.json and direct Nitro to it
5) Run:
   - kurtosis run --enclave arbitrum-preloaded . --args-file args/preloaded.generated.sample.yaml

Notes:
- This path does not emit L1 deployment transactions or require reading L1 init logs; Nitro reads the genesis info-file instead.
- Ensure the genesis info-file rollup addresses and chain-config match the preloaded state you embed.

## Notes
- Modes 3 and 4 do not run the ethereum-package; they are L2-only against an external L1.
- When pointing containers to a host-running L1 RPC:
  - On Linux, use the Docker host gateway IP (often http://172.17.0.1:<mapped-port>) instead of 127.0.0.1, which resolves inside the container.
  - host.docker.internal is not always available on Linux; prefer the 172.17.0.1 form.
- AnyTrust/DAS and Timeboost are excluded.
- To try a different sequencer image, set l2.sequencer.image in the args file.
