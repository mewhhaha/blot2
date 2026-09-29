.PHONY: all test test-build test-no-reference parity clean
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
parity: all
	python3 test_existing.py --report _build/parity.json
clean:
	rm -rf _build
