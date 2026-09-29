.PHONY: all test test-build test-no-reference test-checkpoint parity graph-parity clean
all:
	python3 build.py
test: all
	python3 test_native.py
	python3 test_transport.py _build/blotc
	deno run --allow-all smoke.ts
test-build:
	python3 test_build.py
test-no-reference: all
	python3 test_no_reference.py
graph-parity: all
	python3 test_existing.py --verify-type-graph --report _build/graph-parity.json
test-checkpoint:
	python3 test_checkpoint.py $(CHECKPOINT)
parity: all
	python3 test_existing.py --report _build/parity.json
clean:
	rm -rf _build
