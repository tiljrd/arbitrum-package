load("json.star", "json")

def _json(obj):
    return json.marshal(obj)

def write_configs(plan, l1_config, l2_args):
    chain_id = str(l2_args.get("chain_id", 42161))
    l1_rpc_url = str(l1_config.get("L1_RPC_URL"))
    l1_chain_id = str(l1_config.get("L1_CHAIN_ID"))
    sequencer = l2_args.get("sequencer", {})
    validator = l2_args.get("validator", {})
    batch_poster = l2_args.get("batch_poster", {})
    inbox_reader = l2_args.get("inbox_reader", {})
    validation_node = l2_args.get("validation_node", {})

    l2_chain_config = {
        "chain_id": chain_id,
        "l1": {
            "rpc_url": l1_rpc_url,
            "chain_id": l1_chain_id,
        },
    }

    sequencer_conf = {
        "l2": {
            "chain_id": chain_id,
        },
        "parent_chain": {
            "rpc": {
                "url": l1_rpc_url,
            },
        },
        "node": {
            "rpc": {
                "addr": "0.0.0.0",
                "port": int(sequencer.get("rpc_port", 8547)),
            },
            "ws": {
                "addr": "0.0.0.0",
                "port": int(sequencer.get("ws_port", 8548)),
            },
            "feed": {
                "output": {
                    "enable": True,
                    "port": int(sequencer.get("feed_port", 9642)),
                },
            },
        },
    }

    validator_conf = {
        "l2": {
            "chain_id": chain_id,
        },
        "parent_chain": {
            "rpc": {
                "url": l1_rpc_url,
            },
        },
        "node": {
            "rpc": {
                "addr": "0.0.0.0",
                "port": int(validator.get("rpc_port", 8247)),
            },
            "ws": {
                "addr": "0.0.0.0",
                "port": int(validator.get("ws_port", 8248)),
            },
        },
        "validation": {
            "url": "http://validation-node:{}".format(int(validation_node.get("port", 8549))),
        },
    }

    poster_conf = {
        "l2": {
            "chain_id": chain_id,
        },
        "parent_chain": {
            "rpc": {
                "url": l1_rpc_url,
            },
        },
    }

    inbox_reader_conf = {
        "l2": {
            "chain_id": chain_id,
        },
        "parent_chain": {
            "rpc": {
                "url": l1_rpc_url,
            },
        },
        "node": {
            "inbox_reader": {
                "enable": True,
            },
        },
    }

    validation_node_conf = {
        "rpc": {
            "addr": "0.0.0.0",
            "port": int(validation_node.get("port", 8549)),
        },
    }

    files = {
        "config/l2_chain_config.json": _json(l2_chain_config),
        "config/sequencer_config.json": _json(sequencer_conf),
        "config/validator_config.json": _json(validator_conf),
        "config/poster_config.json": _json(poster_conf),
        "config/inbox_reader_config.json": _json(inbox_reader_conf),
        "config/validation_node_config.json": _json(validation_node_conf),
    }

    artifact = plan.upload_files_artifact(files=files)
    return artifact
