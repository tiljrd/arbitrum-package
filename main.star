# Arbitrum Kurtosis package using arb-reth + Nitro components (scaffold)

def run(plan, args):
    plan.print("Starting Arbitrum package scaffold")

    # Parse args (minimal)
    l1_cfg = args.get("l1", {})
    l2_cfg = args.get("l2", {})
    nitro_cfg = args.get("nitro", {})

    # TODO: networks and subnets as needed
    # net = plan.create_network("arbitrum-net")

    # L1 dev chain (anvil/geth) placeholder
    # TODO: switch to geth if preferred; expose rpc port.
    l1_svc = plan.add_service(
        name="l1",
        config={
            "image": "ghcr.io/foundry-rs/foundry:latest",
            "cmd": ["/bin/sh", "-lc", "anvil --host 0.0.0.0 --port {}".format(l1_cfg.get("rpc_port", 8545))],
            "ports": {"rpc": {"number": l1_cfg.get("rpc_port", 8545), "protocol": "TCP"}},
        },
    )
    plan.print("L1 service added: {}".format(l1_svc))

    # Sequencer with arb-reth local image placeholder
    seq_image = l2_cfg.get("sequencer", {}).get("image", "arb-reth:local")
    seq_rpc = l2_cfg.get("sequencer", {}).get("rpc_port", 8547)
    seq_p2p = l2_cfg.get("sequencer", {}).get("p2p_port", 30303)
    arb_reth = plan.add_service(
        name="arb-reth",
        config={
            "image": seq_image,
            "cmd": ["/usr/local/bin/arb-reth", "--help"],  # TODO: replace with real args/flags
            "ports": {
                "rpc": {"number": seq_rpc, "protocol": "TCP"},
                "p2p": {"number": seq_p2p, "protocol": "TCP"},
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
            "cmd": ["/bin/sh", "-lc", "sleep 3600"],  # TODO: replace with real startup
            "ports": {"rpc": {"number": arbnode_rpc, "protocol": "TCP"}},
        },
    )
    plan.print("Arbnode service added: {}".format(arbnode))

    inbox_reader = plan.add_service(
        name="inbox-reader",
        config={
            "image": nitro_cfg.get("inbox_reader", {}).get("image", "ghcr.io/offchainlabs/nitro:latest"),
            "cmd": ["/bin/sh", "-lc", "sleep 3600"],  # TODO
        },
    )
    batch_poster = plan.add_service(
        name="batch-poster",
        config={
            "image": nitro_cfg.get("batch_poster", {}).get("image", "ghcr.io/offchainlabs/nitro:latest"),
            "cmd": ["/bin/sh", "-lc", "sleep 3600"],  # TODO
        },
    )
    plan.print("Inbox reader and batch poster added.")

    # TODO: health checks, environment wiring, contract deployment, exporting endpoints
    plan.print("Scaffold complete. Replace sleep commands with real startup scripts and wire env/configs.")

    return {
        "success": True,
        "l1_rpc": "http://l1:{}".format(l1_cfg.get("rpc_port", 8545)),
        "l2_rpc": "http://arb-reth:{}".format(seq_rpc),
        "arbnode_rpc": "http://arbnode:{}".format(arbnode_rpc),
    }
