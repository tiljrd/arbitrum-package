utils = import_module("github.com/LZeroAnalytics/optimism-package/src/util.star")

def deploy_rollup(plan, l1_env, l1_network_id, l1_priv_key, l2_args, config_artifact):
    chain_id = str(l2_args.get("chain_id", 42161))
    child_chain_name = str(l2_args.get("name", "arb-dev"))
    seq_addr = l2_args.get("sequencer_address", "")
    owner_addr = l2_args.get("owner_address", "")

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
            "deploy_step1.ts": struct(template=read_file("../templates/deploy_step1.ts.tmpl"), data=struct()),
            "deploy_step2.ts": struct(template=read_file("../templates/deploy_step2.ts.tmpl"), data=struct()),
        },
    )

    env = {
        "CHILD_CHAIN_NAME": child_chain_name,
        "DEPLOYER_PRIVKEY": str(l1_priv_key),
        "PARENT_CHAIN_RPC": l1_env["L1_RPC_URL"],
        "PARENT_CHAIN_ID": str(l1_network_id),
        "CHILD_CHAIN_CONFIG_PATH": "/deploy/l2_chain_config.json",
        "CHAIN_DEPLOYMENT_INFO": "/deploy/deployment.json",
        "CHILD_CHAIN_INFO": "/deploy/deployed_chain_info.json",
    }

    if seq_addr:
        env["SEQUENCER_ADDRESS"] = str(seq_addr)
    if owner_addr:
        env["OWNER_ADDRESS"] = str(owner_addr)

    # Step 1: base tools + clone repo
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

    # Step 2: yarn install
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

    # Step 3: install foundry and build yul
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

    # Step 4: build contracts
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

    # Step 5a: deploy contracts and set templates
    step5a = plan.run_sh(
        name="arb-deploy-step5a-deploy-templates",
        description="Deploy nitro contracts and set templates",
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
            "npx hardhat run --network custom /deploy/deploy_step1.ts",
        ]),
        store=[StoreSpec(src="/deploy", name="arb-deploy-out")],
    )

    # Step 5b: create rollup using deployed templates
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
            "/deploy": step5a.files_artifacts[0],
            "/config": config_artifact,
        },
        run=" && ".join([
            "set -e",
            "cd /src",
            "npx hardhat run --network custom /deploy/deploy_step2.ts",
        ]),
        store=[StoreSpec(src="/deploy", name="arb-deploy-out")],
    )

    # Step 6: finalize l2_chain_info.json
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
