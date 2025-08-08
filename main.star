# Arbitrum Kurtosis package using arb-reth + Nitro components (wired to ethereum package for L1)

ethereum_package = import_module("github.com/LZeroAnalytics/ethereum-package/main.star")

def run(plan, args):
    plan.print("Starting Arbitrum package (ethereum package for L1)")

    eth_pkg_args = args.get("ethereum_package", {})
    l2_cfg = args.get("l2", {})
    nitro_cfg = args.get("nitro", {})

    # Launch L1 via ethereum package, mirroring optimism-package
    plan.print("Deploying a local L1 using ethereum package")
    l1 = ethereum_package.run(plan, eth_pkg_args)
    all_l1_participants = l1.all_participants
    l1_network_params = l1.network_params
    l1_network_id = l1.network_id
    l1_rpc_url = all_l1_participants[0].el_context.rpc_http_url

    # Sequencer with arb-reth local image placeholder
    seq_image = l2_cfg.get("sequencer", {}).get("image", "arb-reth:local")
    seq_rpc = l2_cfg.get("sequencer", {}).get("rpc_port", 8547)
    seq_p2p = l2_cfg.get("sequencer", {}).get("p2p_port", 30303)
    arb_reth = plan.add_service(
        name="arb-reth",
        config={
            "image": seq_image,
            "cmd": [
                "/usr/local/bin/arb-reth",
                "node",
                "--chain", "dev",
                "--http",
                "--http.addr", "0.0.0.0",
                "--http.port", str(seq_rpc),
                "--authrpc.addr", "0.0.0.0",
                "--authrpc.port", "8551",
                "--rollup.compute-pending-block"
            ],
            "ports": {
                "rpc": {"number": seq_rpc, "protocol": "TCP"},
                "engine": {"number": 8551, "protocol": "TCP"},
                "p2p": {"number": seq_p2p, "protocol": "TCP"}
            },
            "env_vars": {
                "L1_RPC_URL": str(l1_rpc_url),
                "L1_CHAIN_ID": str(l1_network_id),
            },
        },
    )
    plan.print("Sequencer service added: {}".format(arb_reth))

    # Nitro components placeholders
    arbnode_image = nitro_cfg.get("arbnode", {}).get("image", "ghcr.io/offchainlabs/nitro:latest")
    arbnode_rpc = nitro_cfg.get("arbnode", {}).get("rpc_port", 8549)
    arbnode = plan.add_service(
        name="arbnode",
        config={
            "image": arbnode_image,
            "cmd": [
                "/usr/local/bin/nitro",
                "--http.addr", "0.0.0.0",
                "--http.port", str(arbnode_rpc),
                "--http.api", "net,web3,eth,txpool,debug",
                "--parent-chain.url", str(l1_rpc_url),
                "--execution.engine", "http://arb-reth:8551",
                "--execution.engine.auth", "",
                "--node.sequencer", "true",
                "--node.feed.output.enable",
                "--node.feed.output.port", "9642"
            ],
            "ports": {
                "rpc": {"number": arbnode_rpc, "protocol": "TCP"},
                "feed": {"number": 9642, "protocol": "TCP"}
            },
            "env_vars": {
                "L1_RPC_URL": str(l1_rpc_url),
                "L1_CHAIN_ID": str(l1_network_id),
            },
        },
    )
    plan.print("Arbnode service added: {}".format(arbnode))

    inbox_reader = plan.add_service(
        name="inbox-reader",
        config={
            "image": nitro_cfg.get("inbox_reader", {}).get("image", "ghcr.io/offchainlabs/nitro:latest"),
            "cmd": [
                "/usr/local/bin/nitro",
                "--parent-chain.url", str(l1_rpc_url),
                "--node.rpc.addr", "http://arbnode:{}".format(arbnode_rpc),
                "--node.inbox-reader", "true"
            ],
            "env_vars": {
                "L1_RPC_URL": str(l1_rpc_url),
                "L1_CHAIN_ID": str(l1_network_id),
            },
        },
    )
    batch_poster = plan.add_service(
        name="batch-poster",
        config={
            "image": nitro_cfg.get("batch_poster", {}).get("image", "ghcr.io/offchainlabs/nitro:latest"),
            "cmd": [
                "/usr/local/bin/nitro",
                "--parent-chain.url", str(l1_rpc_url),
                "--node.rpc.addr", "http://arbnode:{}".format(arbnode_rpc),
                "--node.batch-poster", "true"
            ],
            "env_vars": {
                "L1_RPC_URL": str(l1_rpc_url),
                "L1_CHAIN_ID": str(l1_network_id),
            },
        },
    )
    plan.print("Inbox reader and batch poster added.")

    # TODO: replace sleeps with real commands and wire env for L1/L2 connectivity
    plan.print("Scaffold complete. Wire arb-reth/arbnode/inbox/batch to L1 RPC and rollup configs.")

    return {
        "success": True,
        "l1_rpc": str(l1_rpc_url),
        "l2_rpc": "http://arb-reth:{}".format(seq_rpc),
        "arbnode_rpc": "http://arbnode:{}".format(arbnode_rpc),
        "l1_chain_id": str(l1_network_id),
    }
