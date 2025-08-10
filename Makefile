.PHONY: gen-preloaded
gen-preloaded:
	node tools/gen-preloaded.mjs --rpc "$(RPC)" --contracts "$(CONTRACTS)" --block "$(BLOCK)" --out "$(OUT)" --encoding $(ENCODING)
