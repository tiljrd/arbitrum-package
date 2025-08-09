ethereum_package = import_module("github.com/ethpandaops/ethereum-package/main.star")
config_mod = import_module("./src/config.star")
deployer = import_module("./src/deployer.star")
blockscout = import_module("github.com/LZeroAnalytics/blockscout-package/main.star")

def run(plan, args={}):
    ethereum_args = args.get("ethereum_package", {})
    l2_args = args.get("l2", {})
    blockscout_args = args.get("blockscout", {})
    logging_args = args.get("logging", {})

    l1 = ethereum_package.run(plan, ethereum_args)
    all_l1_participants = l1.all_participants
    l1_rpc_url = all_l1_participants[0].el_context.rpc_http_url
    l1_ws_url = all_l1_participants[0].el_context.ws_url
    l1_cl_url = all_l1_participants[0].cl_context.beacon_http_url
    l1_chain_id = l1.network_id
    # Use index 12 for L2 contract deployments, mirroring optimism-package
    l1_priv_key = l1.pre_funded_accounts[12].private_key

    l1_env = {
        "L1_RPC_KIND": "standard",
        "WEB3_RPC_URL": str(l1_rpc_url),
        "L1_RPC_URL": str(l1_rpc_url),
        "CL_RPC_URL": str(l1_cl_url),
        "L1_WS_URL": str(l1_ws_url),
        "L1_CHAIN_ID": str(l1_chain_id),
    }

    cfg_artifact = config_mod.write_configs(plan, l1_env, l2_args, l1_priv_key)

    deploy_artifact = deployer.deploy_rollup(
        plan=plan,
        l1_env=l1_env,
        l1_network_id=l1_chain_id,
        l1_priv_key=l1_priv_key,
        l2_args=l2_args,
        config_artifact=cfg_artifact,
    )

    valnode_image = l2_args.get("validation_node", {}).get("image", "ghcr.io/offchainlabs/nitro:latest")
    valnode_port = int(l2_args.get("validation_node", {}).get("port", 8549))
    validation_node = plan.add_service(
        name="validation-node",
        config=ServiceConfig(
            image=valnode_image,
            entrypoint=["/usr/local/bin/nitro-val"],
            cmd=["--conf.file=/config/validation_node_config.json"],
            files={"/config": cfg_artifact, "/deploy": deploy_artifact},
            ports={
                "rpc": PortSpec(number=valnode_port, transport_protocol="TCP"),
            },
        ),
    )

    seq_image = l2_args.get("sequencer", {}).get("image", "ghcr.io/offchainlabs/nitro:latest")
    seq_rpc = int(l2_args.get("sequencer", {}).get("rpc_port", 8547))
    seq_ws = int(l2_args.get("sequencer", {}).get("ws_port", 8548))
    seq_feed = int(l2_args.get("sequencer", {}).get("feed_port", 9642))
    sequencer = plan.add_service(
        name="sequencer",
        config=ServiceConfig(
            image=seq_image,
            entrypoint=["/usr/local/bin/nitro"],
            cmd=[
                "--conf.file=/config/sequencer_config.json",
                "--node.parent-chain-reader.use-finality-data=false",
                "--node.feed.output.enable",
                "--node.feed.output.port={}".format(seq_feed),
                "--http.api=net,web3,eth,txpool,debug,auctioneer",
                "--graphql.enable",
                "--graphql.vhosts=*",
                "--graphql.corsdomain=*",
            ],
            files={"/config": cfg_artifact, "/deploy": deploy_artifact},
            ports={
                "rpc": PortSpec(number=seq_rpc, transport_protocol="TCP"),
                "ws": PortSpec(number=seq_ws, transport_protocol="TCP"),
                "feed": PortSpec(number=seq_feed, transport_protocol="TCP"),
            },
        ),
    )

    inbox_image = l2_args.get("inbox_reader", {}).get("image", "ghcr.io/offchainlabs/nitro:latest")
    inbox_reader = plan.add_service(
        name="inbox-reader",
        config=ServiceConfig(
            image=inbox_image,
            entrypoint=["/usr/local/bin/nitro"],
            cmd=[
                "--conf.file=/config/inbox_reader_config.json",
                "--node.parent-chain-reader.use-finality-data=false",
            ],
            files={"/config": cfg_artifact, "/deploy": deploy_artifact},
        ),
    )

    poster_image = l2_args.get("batch_poster", {}).get("image", "ghcr.io/offchainlabs/nitro:latest")
    batch_poster = plan.add_service(
        name="batch-poster",
        config=ServiceConfig(
            image=poster_image,
            entrypoint=["/usr/local/bin/nitro"],
            cmd=[
                "--conf.file=/config/poster_config.json",
                "--node.parent-chain-reader.use-finality-data=false",
                "--node.batch-poster.l1-block-bound=latest",
            ],
            files={"/config": cfg_artifact, "/deploy": deploy_artifact},
        ),
    )

    use_validator = bool(l2_args.get("use_validator", True))
    validator_rpc = ""
    if use_validator:
        val_image = l2_args.get("validator", {}).get("image", "ghcr.io/offchainlabs/nitro:latest")
        val_rpc = int(l2_args.get("validator", {}).get("rpc_port", 8247))
        val_ws = int(l2_args.get("validator", {}).get("ws_port", 8248))
        plan.add_service(
            name="validator",
            config=ServiceConfig(
                image=val_image,
                entrypoint=["/usr/local/bin/nitro"],
                cmd=[
                    "--conf.file=/config/validator_config.json",
                    "--http.api=net,web3,arb,debug",
                ],
                files={"/config": cfg_artifact, "/deploy": deploy_artifact},
                ports={
                    "rpc": PortSpec(number=val_rpc, transport_protocol="TCP"),
                    "ws": PortSpec(number=val_ws, transport_protocol="TCP"),
                },
            ),
        )
        validator_rpc = "http://validator:{}".format(val_rpc)

    bs_output = {}
    if bool(blockscout_args.get("enabled", False)):
        network_name = str(l2_args.get("name", "ArbitrumLocal"))
        coin = str(blockscout_args.get("coin", "ETH"))
        ethereum_cfg = {
            "rpc_url": "http://sequencer:{}".format(seq_rpc),
            "ws_url": "ws://sequencer:{}".format(seq_ws),
            "client_name": "geth",
            "extra_env_vars": {
                "NETWORK": network_name,
                "SUBNETWORK": network_name,
                "COIN": coin,
            },
            "frontend_env_vars": {
                "NEXT_PUBLIC_NETWORK_NAME": network_name,
            },
        }
        general_cfg = {
             "network_name": network_name,
             "network_id": str(l2_args.get("chain_id", 42161)),
             "coin": coin,
             "is_testnet": "true",
             "blockscout_image": "ghcr.io/blockscout/blockscout:latest",
             "blockscout_frontend_image": "ghcr.io/blockscout/frontend:latest",
         }
        bs_output = blockscout.run(
            plan,
            general_args=general_cfg,
            ethereum_args=ethereum_cfg,
        )

    return {
        "l1_rpc_url": str(l1_rpc_url),
        "l1_chain_id": str(l1_chain_id),
        "l2_rpc_url": "http://sequencer:{}".format(seq_rpc),
        "validation_api_url": "http://validation-node:{}".format(valnode_port),
        "validator_rpc_url": validator_rpc,
        "blockscout_url": bs_output.get("blockscout_url", ""),
        "blockscout_frontend_url": bs_output.get("frontend_url", ""),
        "blockscout_verification_url": bs_output.get("verification_url", ""),
    }
