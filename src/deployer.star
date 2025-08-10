utils = import_module("github.com/LZeroAnalytics/optimism-package/src/util.star")

def deploy_rollup(plan, l1_env, l1_network_id, l1_priv_key, l2_args, config_artifact,
                  deploy_mode="deploy", target="internal",
                  precomputed_artifacts={}, contract_addresses={}):
    chain_id = str(l2_args.get("chain_id", 42161))
    child_chain_name = str(l2_args.get("name", "arb-dev"))
    seq_addr = l2_args.get("sequencer_address", "")
    owner_addr = l2_args.get("owner_address", "")

    if deploy_mode == "skip":
        files_cfg = {}
        cj = str(precomputed_artifacts.get("contracts_json", ""))
        dj = str(precomputed_artifacts.get("deployed_chain_info_json", ""))
        lj = str(precomputed_artifacts.get("l2_chain_info_json", ""))
        gj = str(precomputed_artifacts.get("l2_chain_info_genesis_json", ""))
        if cj != "":
            files_cfg["contracts.json"] = struct(template=cj, data=struct())
        if dj != "":
            files_cfg["deployed_chain_info.json"] = struct(template=dj, data=struct())
        if lj != "":
            files_cfg["l2_chain_info.json"] = struct(template=lj, data=struct())
        if gj != "":
            files_cfg["l2_chain_info.genesis.json"] = struct(template=gj, data=struct())
        if len(files_cfg.keys()) == 0:
            fail("deploy_mode=skip requires precomputed_artifacts to include at least one of: contracts_json, deployed_chain_info_json, l2_chain_info_json, l2_chain_info_genesis_json")
        artifact = plan.render_templates(
            name="arb-deploy-out",
            description="Arbitrum rollup precomputed artifacts",
            config=files_cfg,
        )
        return artifact

    deploy_files = plan.render_templates(
        name="arb-deploy-out",
        description="Arbitrum rollup deploy output holder",
        config={
            "l2_chain_config.json": struct(template=read_file("../templates/l2_chain_config.json.tmpl"), data=struct(
                ChainID=chain_id,
                L1RPCURL=l1_env["L1_RPC_URL"],
                L1ChainID=l1_env["L1_CHAIN_ID"],
            )),
            "scripts/config.ts": struct(template=read_file("../templates/config.ts.tmpl"), data=struct(
                ChainID=chain_id,
            )),
            "deploy_step1a_core.ts": struct(template=read_file("../templates/deploy_step1a_core.ts.tmpl"), data=struct()),
            "deploy_step1b_provers.ts": struct(template=read_file("../templates/deploy_step1b_provers.ts.tmpl"), data=struct()),
            "deploy_step1c_rest.ts": struct(template=read_file("../templates/deploy_step1c_rest.ts.tmpl"), data=struct()),
            "deploy_step2.ts": struct(template=read_file("../templates/deploy_step2.ts.tmpl"), data=struct()),
        },
    )

    env = {
        "CHILD_CHAIN_NAME": child_chain_name,
        "DEPLOYER_PRIVKEY": str(l1_priv_key),
        "PARENT_CHAIN_RPC": l1_env["L1_RPC_URL"],
        "PARENT_CHAIN_ID": str(l1_network_id),
        "CHILD_CHAIN_CONFIG_PATH": "/config/l2_chain_config.json",
        "CHAIN_DEPLOYMENT_INFO": "/deploy/deployment.json",
        "CHILD_CHAIN_INFO": "/deploy/deployed_chain_info.json",
    }

    if seq_addr:
        env["SEQUENCER_ADDRESS"] = str(seq_addr)
    if owner_addr:
        env["OWNER_ADDRESS"] = str(owner_addr)

    step1 = plan.run_sh(
        name="arb-deploy-step1-clone",
        description="Install base tools and clone nitro-contracts",
        image="node:20-bookworm",
        files={"/deploy": deploy_files},
        run=" && ".join([
            "set -e",
            "apt-get update && apt-get install -y git jq python3 build-essential curl ca-certificates pkg-config libssl-dev",
            "corepack enable",
            "git clone --depth 1 --branch v3.1.0 https://github.com/OffchainLabs/nitro-contracts.git /src",
            "cp /deploy/scripts/config.ts /src/scripts/config.ts",
        ]),
        store=[StoreSpec(src="/src", name="arb-deploy-src")],
    )
    src_art = step1.files_artifacts[0]

    step2 = plan.run_sh(
        name="arb-deploy-step2-yarn-install",
        description="Install JS dependencies",
        image="node:20-bookworm",
        files={"/src": src_art},
        run=" && ".join([
            "set -e",
            "cd /src",
            "yarn install --frozen-lockfile || yarn install",
        ]),
        store=[StoreSpec(src="/src", name="arb-deploy-src")],
    )
    src_art = step2.files_artifacts[0]

    step3 = plan.run_sh(
        name="arb-deploy-step3-foundry",
        description="Install Foundry and build YUL artifacts",
        image="node:20-bookworm",
        files={"/src": src_art},
        run=" && ".join([
            "set -e",
            "curl -L https://foundry.paradigm.xyz | bash",
            ". /root/.bashrc || true",
            "/root/.foundry/bin/foundryup",
            "cd /src",
            "yarn build:forge:yul || true",
        ]),
        store=[StoreSpec(src="/src", name="arb-deploy-src")],
    )
    src_art = step3.files_artifacts[0]

    step4 = plan.run_sh(
        name="arb-deploy-step4-build",
        description="Build nitro-contracts",
        image="node:20-bookworm",
        files={"/src": src_art},
        run=" && ".join([
            "set -e",
            "cd /src",
            "yarn build || yarn run build || true",
        ]),
        store=[StoreSpec(src="/src", name="arb-deploy-src")],
    )
    src_art = step4.files_artifacts[0]

    wait_l1 = plan.run_sh(
        name="arb-deploy-wait-l1",
        description="Wait for external L1 RPC to be ready",
        image="node:20-bookworm",
        env_vars=dict(env, **{
            "CUSTOM_RPC_URL": l1_env["L1_RPC_URL"],
        }),
        run=" && ".join([
            "set -e",
            "apt-get update && apt-get install -y curl",
            "echo Waiting for L1 RPC at $CUSTOM_RPC_URL with chainId $PARENT_CHAIN_ID",
            "for i in $(seq 1 60); do RES=$(curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_version\",\"params\":[],\"id\":1}' $CUSTOM_RPC_URL || true); echo $RES | grep -q '\"result\"' && break || true; sleep 2; done",
            "sleep 5"
        ]),
    )

    step5a1 = plan.run_sh(
        name="arb-deploy-step5a1-core",
        description="Deploy core bridge and inbox contracts",
        image="node:20-bookworm",
        env_vars=dict(env, **{
            "CUSTOM_RPC_URL": l1_env["L1_RPC_URL"],
            "DISABLE_VERIFICATION": "true",
            "IGNORE_MAX_DATA_SIZE_WARNING": "true",
            "MAX_DATA_SIZE": "117964",
            "CONTRACTS_OUT_PATH": "/deploy/contracts.json",
        }),
        files={
            "/src": src_art,
            "/deploy": deploy_files,
        },
        run=" && ".join([
            "set -e",
            "cd /src",
            "cp /deploy/deploy_step1a_core.ts /src/deploy_step1a_core.ts",
            "npx hardhat run --network custom ./deploy_step1a_core.ts",
        ]),
        store=[StoreSpec(src="/deploy", name="arb-deploy-out")],
    )

    step5a2 = plan.run_sh(
        name="arb-deploy-step5a2-provers",
        description="Deploy prover contracts",
        image="node:20-bookworm",
        env_vars=dict(env, **{
            "CUSTOM_RPC_URL": l1_env["L1_RPC_URL"],
            "DISABLE_VERIFICATION": "true",
            "IGNORE_MAX_DATA_SIZE_WARNING": "true",
            "CONTRACTS_OUT_PATH": "/deploy/contracts.json",
        }),
        files={
            "/src": src_art,
            "/deploy": step5a1.files_artifacts[0],
        },
        run=" && ".join([
            "set -e",
            "cd /src",
            "cp /deploy/deploy_step1b_provers.ts /src/deploy_step1b_provers.ts",
            "npx hardhat run --network custom ./deploy_step1b_provers.ts",
        ]),
        store=[StoreSpec(src="/deploy", name="arb-deploy-out")],
    )

    step5a3 = plan.run_sh(
        name="arb-deploy-step5a3-rest",
        description="Deploy remaining contracts and set templates",
        image="node:20-bookworm",
        env_vars=dict(env, **{
            "CUSTOM_RPC_URL": l1_env["L1_RPC_URL"],
            "DISABLE_VERIFICATION": "true",
            "IGNORE_MAX_DATA_SIZE_WARNING": "true",
            "CONTRACTS_OUT_PATH": "/deploy/contracts.json",
        }),
        files={
            "/src": src_art,
            "/deploy": step5a2.files_artifacts[0],
        },
        run=" && ".join([
            "set -e",
            "cd /src",
            "cp /deploy/deploy_step1c_rest.ts /src/deploy_step1c_rest.ts",
            "npx hardhat run --network custom ./deploy_step1c_rest.ts",
        ]),
        store=[StoreSpec(src="/deploy", name="arb-deploy-out")],
    )

    wasmroot_step = plan.run_sh(
        name="arb-deploy-step5a4-wasmroot",
        description="Read WASM module root from nitro-node image",
        image="offchainlabs/nitro-node:v3.6.7-a7c9f1e",
        run=" && ".join([
            "set -e",
            "mkdir -p /tmp",
            "cat /home/user/target/machines/latest/module-root.txt > /tmp/wasmroot",
            "echo Read WASM module root: $(cat /tmp/wasmroot)"
        ]),
        store=[StoreSpec(src="/tmp", name="arb-wasm-root")],
    )

    step5b = plan.run_sh(
        name="arb-deploy-step5b-create-rollup",
        description="Create rollup using RollupCreator",
        image="node:20-bookworm",
        env_vars=dict(env, **{
            "CUSTOM_RPC_URL": l1_env["L1_RPC_URL"],
            "DISABLE_VERIFICATION": "true",
            "IGNORE_MAX_DATA_SIZE_WARNING": "true",
            "CONTRACTS_OUT_PATH": "/deploy/contracts.json",
        }),
        files={
            "/src": src_art,
            "/deploy": step5a3.files_artifacts[0],
            "/wasm": wasmroot_step.files_artifacts[0],
            "/config": config_artifact,
        },
        run=" && ".join([
            "set -e",
            "cd /src",
            "cp /deploy/deploy_step2.ts /src/deploy_step2.ts",
            "cp /wasm/wasmroot /deploy/wasmroot",
            "export WASM_MODULE_ROOT=$(cat /deploy/wasmroot)",
            "echo Using WASM_MODULE_ROOT=$WASM_MODULE_ROOT",
            "npx hardhat run --network custom ./deploy_step2.ts",
        ]),
        store=[StoreSpec(src="/deploy", name="arb-deploy-out")],
    )

    finalize = plan.run_sh(
        name="arb-deploy-step6-finalize",
        description="Finalize l2_chain_info.json from deployed_chain_info.json",
        image="node:20-bookworm",
        files={"/deploy": step5b.files_artifacts[0]},
        run=" && ".join([
            "set -e",
            "cp /deploy/deployed_chain_info.json /deploy/l2_chain_info.json",
        ]),
        store=[StoreSpec(src="/deploy", name="arb-deploy-out")],
    )

    return finalize.files_artifacts[0]
