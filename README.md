# Arbitrum Kurtosis Package

This package launches a simple Arbitrum One–equivalent local network:
- L1 via ethereum-package
- Core Nitro L2 services: sequencer, inbox-reader, batch-poster, validator, validation-node
- No AnyTrust/DAS and no Timeboost in this iteration
- Structured so the sequencer can be swapped to a custom arb-reth later

## Prerequisites
- Kurtosis CLI installed

## Run
```
kurtosis clean -a
kurtosis run --enclave arbitrum . --args-file args/minimal.yaml
```

## Args
See args/minimal.yaml. It uses ethereum-package defaults for L1 and configures Nitro service images and ports.

## Endpoints
- L1 RPC: printed as l1_rpc_url
- L2 RPC (sequencer): printed as l2_rpc_url
- Validation API (validation-node): printed as validation_api_url
- Validator RPC: printed as validator_rpc_url (when use_validator is true)

## Logs
```
kurtosis service logs arbitrum sequencer
kurtosis service logs arbitrum validator
kurtosis service logs arbitrum validation-node
```

## Notes
- AnyTrust/DAS and Timeboost are excluded.
- Blockscout can be added later.
- To try a different sequencer image in the future, set l2.sequencer.image in the args file.
