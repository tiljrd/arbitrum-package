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

    out = plan.run_sh(
        name="arb-rollup-deploy",
        description="Deploy Arbitrum rollup and produce l2_chain_info.json",
        image="node:20-bullseye",
        env_vars=env,
        files={
            "/deploy": deploy_files,
            "/config": config_artifact,
        },
        run=" && ".join([
            "set -e",
            "apt-get update && apt-get install -y git jq",
            "corepack enable",
            "git clone https://github.com/OffchainLabs/nitro-contracts.git /src",
            "cd /src",
            "yarn install --frozen-lockfile || yarn install",
            "yarn build || yarn run build || true",
            "yarn run create-rollup-testnode",
            "cp /deploy/deployed_chain_info.json /deploy/l2_chain_info.json"
        ]),
        store=[StoreSpec(src="/deploy", name="arb-deploy-out")],
    )

    return out.files_artifacts[0]
