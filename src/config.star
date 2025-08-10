def write_configs(plan, l1_config, l2_args, l1_priv_key):
    chain_id = str(l2_args.get("chain_id", 42161))
    l1_rpc_url = str(l1_config.get("L1_RPC_URL"))
    l1_chain_id = str(l1_config.get("L1_CHAIN_ID"))
    sequencer = l2_args.get("sequencer", {})
    validator = l2_args.get("validator", {})
    validation_node = l2_args.get("validation_node", {})
    info_file_path = str(l2_args.get("info_file_path", "/deploy/l2_chain_info.json"))
    no_l1_listener = bool(l2_args.get("no_l1_listener", False))

    key = str(l1_priv_key)
    if key.startswith("0x") or key.startswith("0X"):
        key = key[2:]

    owner_addr = str(l2_args.get("owner_address", "0x3f1Eae7D46d88F08fc2F8ed27FCb2AB183EB2d0E"))
    if not (owner_addr.startswith("0x") or owner_addr.startswith("0X")):
        owner_addr = "0x" + owner_addr

    data = struct(
        ChainID=chain_id,
        L1RPCURL=l1_rpc_url,
        L1ChainID=l1_chain_id,
        OwnerAddress=owner_addr,
        SeqRPC=int(sequencer.get("rpc_port", 8547)),
        SeqWS=int(sequencer.get("ws_port", 8548)),
        SeqFeed=int(sequencer.get("feed_port", 9642)),
        ValRPC=int(validator.get("rpc_port", 8247)),
        ValWS=int(validator.get("ws_port", 8248)),
        ValNodePort=int(validation_node.get("port", 8549)),
        ValJwtSecret="/config/val_jwt.hex",
        L1PrivKey=key,
        InfoFilePath=info_file_path,
        NoL1Listener=no_l1_listener,
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
