COBC := cobc
CFLAGS := -free -I copybooks
RUNENV := BANK_HOME=$(CURDIR) COB_LIBRARY_PATH=$(CURDIR)/build

.PHONY: build test clean bank eod dirs seed

dirs:
	@mkdir -p build var/data var/journal var/audit var/out var/in var/run

build: dirs
	@for f in cobol/*/*.cbl; do \
		n=$$(basename $$f .cbl); \
		$(COBC) $(CFLAGS) -m -o build/$$n.so $$f || exit 1; \
	done
	$(COBC) $(CFLAGS) -x -o build/bank cobol/core/BANKCLI.cbl

test: build
	@$(RUNENV) tests/run.sh

bank: build
	@$(RUNENV) build/bank

seed: build
	@printf 'ledger.init\n' | $(RUNENV) build/bank

eod: build
	@$(RUNENV) build/bank < operations/eod.req

clean:
	rm -rf build var/data var/journal var/audit
