COBC := cobc
CC := cc
KOF ?= kof
CFLAGS := -free -I copybooks
RUNENV := BANK_HOME=$(CURDIR) COB_LIBRARY_PATH=$(CURDIR)/build

.PHONY: build test concurrency-test clean bank eod dirs seed kof-test kof-example kof-facade-test kof-portal

dirs:
	@mkdir -p build var/data var/journal var/audit var/out var/in var/run

build: dirs
	@for f in cobol/*/*.cbl; do \
		n=$$(basename $$f .cbl); \
		$(COBC) $(CFLAGS) -m -o build/$$n.so $$f || exit 1; \
	done
	@$(CC) -O2 -fPIC -shared -o build/KFLOCK.so cobol/foundation/KFLOCK.c || exit 1
	@$(CC) -O2 -o build/lockhelper tests/lockhelper.c -ldl || exit 1
	$(COBC) $(CFLAGS) -x -o build/bank cobol/core/BANKCLI.cbl

test: build
	@$(RUNENV) tests/run.sh
	@$(RUNENV) bash tests/concurrency.sh

concurrency-test: build
	@$(RUNENV) bash tests/concurrency.sh

kof-test: build
	@mkdir -p tools/kof/build
	@cat tools/kof/src/KofBank.kf tools/kof/src/Main.kf > tools/kof/build/Integration.kf
	@$(RUNENV) tests/run.sh --reset-only
	@cd tools/kof/build && $(RUNENV) $(KOF) run Integration.kf

kof-example: build
	@mkdir -p tools/kof/exbuild
	@cat tools/kof/src/KofBank.kf tools/kof/examples/Payroll.kf > tools/kof/exbuild/payroll.kf
	@$(RUNENV) tests/run.sh --reset-only
	@cd tools/kof/exbuild && $(RUNENV) $(KOF) run payroll.kf

bank: build
	@$(RUNENV) build/bank

seed: build
	@printf 'ledger.init\n' | $(RUNENV) build/bank

eod: build
	@$(RUNENV) build/bank < operations/eod.req

kof-facade-test: build
	@for suite in A B C D E F G H I; do \
		$(RUNENV) tests/run.sh --reset-only; \
		mkdir -p tools/kof/facadetest$$suite; \
		cat tools/kof/src/KofBank.kf tools/kof/facade/BffTypes.kf tools/kof/facade/Bff.kf tools/kof/facade/Portal.kf tools/kof/facade/Tools.kf tools/kof/facade/Suite$$suite.kf > tools/kof/facadetest$$suite/FacadeSuite$$suite.kf; \
		(cd tools/kof/facadetest$$suite && $(RUNENV) $(KOF) run FacadeSuite$$suite.kf) || exit 1; \
	done

kof-portal: build
	@mkdir -p tools/kof/portalrun
	@cat tools/kof/src/KofBank.kf tools/kof/facade/BffTypes.kf tools/kof/facade/Bff.kf tools/kof/facade/Portal.kf tools/kof/facade/Demo.kf > tools/kof/portalrun/PortalDemo.kf
	@$(RUNENV) tests/run.sh --reset-only
	@cd tools/kof/portalrun && $(RUNENV) $(KOF) run PortalDemo.kf

clean:
	rm -rf build var/data var/journal var/audit tools/kof/build tools/kof/exbuild tools/kof/facadetest* tools/kof/portalrun
