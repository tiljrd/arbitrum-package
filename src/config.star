def write_configs(plan, l1_config, l2_args):
    chain_id = str(l2_args.get("chain_id", 42161))
    l1_rpc_url = str(l1_config.get("L1_RPC_URL"))
    l1_chain_id = str(l1_config.get("L1_CHAIN_ID"))
    sequencer = l2_args.get("sequencer", {})
    validator = l2_args.get("validator", {})
    validation_node = l2_args.get("validation_node", {})

    data = struct(
        ChainID=chain_id,
        L1RPCURL=l1_rpc_url,
        L1ChainID=l1_chain_id,
        SeqRPC=int(sequencer.get("rpc_port", 8547)),
        SeqWS=int(sequencer.get("ws_port", 8548)),
        SeqFeed=int(sequencer.get("feed_port", 9642)),
        ValRPC=int(validator.get("rpc_port", 8247)),
        ValWS=int(validator.get("ws_port", 8248)),
        ValNodePort=int(validation_node.get("port", 8549)),
        ValJwtSecret="devinlocaljwt",
    )

    artifact = plan.render_templates(
        name="nitro-configs",
        description="Generated Nitro service configs",
        config={
            "l2_chain_config.json": struct(template=read_file("../templates/l2_chain_config.json.tmpl"), data=data),
            "sequencer_config.json": struct(template=read_file("../templates/sequencer_config.json.tmpl"), data=data),
            "validator_config.json": struct(template=read_file("../templates/validator_config.json.tmpl"), data=data),
            "poster_config.json": struct(template=read_file("../templates/poster_config.json.tmpl"), data=data),
            "inbox_reader_config.json": struct(template=read_file("../templates/inbox_reader_config.json.tmpl"), data=data),
            "validation_node_config.json": struct(template=read_file("../templates/validation_node_config.json.tmpl"), data=data),
            "val_jwt.hex": struct(template=read_file("../templates/val_jwt.hex.tmpl"), data=data),
        },
    )
    return artifact
