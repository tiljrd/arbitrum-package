.PHONY: gen-preloaded
.PHONY: gen-genesis-info
gen-genesis-info:
\tnode tools/gen-genesis-info.mjs --deployed "$(DEPLOYED)" --l2config "$(L2CONFIG)" --out "$(OUT)"
gen-preloaded:
	node tools/gen-preloaded.mjs --rpc "$(RPC)" --contracts "$(CONTRACTS)" --block "$(BLOCK)" --out "$(OUT)" --encoding $(ENCODING)
