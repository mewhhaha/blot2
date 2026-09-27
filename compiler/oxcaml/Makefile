OCAMLOPT ?= ocamlopt
BUILD := _build

.PHONY: all test clean
all: $(BUILD)/test_bytes

$(BUILD):
	mkdir -p $@

$(BUILD)/test_bytes: wasm_bytes.ml test_bytes.ml | $(BUILD)
	cp wasm_bytes.ml test_bytes.ml $(BUILD)/
	cd $(BUILD) && $(OCAMLOPT) -g -o test_bytes wasm_bytes.ml test_bytes.ml

test: all
	$(BUILD)/test_bytes

clean:
	rm -rf $(BUILD)
