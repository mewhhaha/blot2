OCAMLOPT ?= ocamlopt
OCAMLFLAGS ?= -g -w -8-11-26-27
BUILD := _build
MODULES := $(shell cat core/modules.txt 2>/dev/null)
CORE := $(addprefix core/,$(addsuffix .ml,$(filter-out ox_native_transport,$(MODULES))))

.PHONY: all bootstrap test clean
all: $(BUILD)/blotc

bootstrap:
	python3 bootstrap/port.py

$(BUILD):
	mkdir -p $@

$(BUILD)/blotc: base.ml ox_native_transport.ml driver.ml core/modules.txt $(CORE) | $(BUILD)
	cp base.ml ox_native_transport.ml driver.ml $(CORE) $(BUILD)/
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -o blotc base.ml $(addsuffix .ml,$(MODULES)) driver.ml

$(BUILD)/test_bytes: wasm_bytes.ml test_bytes.ml | $(BUILD)
	cp wasm_bytes.ml test_bytes.ml $(BUILD)/
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -o test_bytes wasm_bytes.ml test_bytes.ml

$(BUILD)/test_runtime: $(BUILD)/blotc test_runtime.ml
	cp test_runtime.ml $(BUILD)/
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -o test_runtime base.cmx ox_model.cmx ox_numeric_literal.cmx ox_index.cmx test_runtime.ml

test: all $(BUILD)/test_bytes $(BUILD)/test_runtime
	$(BUILD)/test_bytes
	$(BUILD)/test_runtime
	python3 test_transport.py $(BUILD)/blotc

clean:
	rm -rf $(BUILD)
