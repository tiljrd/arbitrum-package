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
- AnyTrust/DAS and Timeboost are excluded.
- To try a different sequencer image, set l2.sequencer.image in the args file.
