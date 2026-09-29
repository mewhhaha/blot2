.PHONY: all test parity clean
all:
	python3 build.py
test: all
	python3 test_native.py
	python3 test_transport.py _build/blotc
	deno run --allow-all smoke.ts
parity: all
	python3 test_existing.py --report _build/parity.json
clean:
	rm -rf _build
