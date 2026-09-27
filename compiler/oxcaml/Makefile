OCAMLOPT ?= ocamlopt
OCAMLFLAGS ?= -g -w -8-11-26-27
BUILD := _build
OCAML_MAJOR := $(shell $(OCAMLOPT) -version | cut -d. -f1)
PARALLEL := $(shell test "$(OCAML_MAJOR)" -ge 5 && echo domains || echo serial)
MODULES := $(shell cat core/modules.txt 2>/dev/null)
CORE := $(addprefix core/,$(addsuffix .ml,$(filter-out ox_native_transport,$(MODULES))))

.PHONY: all bootstrap test clean
all: $(BUILD)/blotc

bootstrap:
	python3 bootstrap/port.py

$(BUILD):
	mkdir -p $@

$(BUILD)/native_parallel.ml: native_parallel_$(PARALLEL).ml Makefile | $(BUILD)
	cp $< $@

$(BUILD)/blotc: base.ml native_runtime.ml runtime_stubs.c ox_native_transport.ml driver.ml core/modules.txt $(CORE) $(BUILD)/native_parallel.ml | $(BUILD)
	cp base.ml native_runtime.ml runtime_stubs.c ox_native_transport.ml driver.ml $(CORE) $(BUILD)/
	cd $(BUILD) && $(OCAMLOPT) -c runtime_stubs.c
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -I +threads -o blotc unix.cmxa threads.cmxa runtime_stubs.o native_runtime.ml native_parallel.ml base.ml $(addsuffix .ml,$(MODULES)) driver.ml

$(BUILD)/test_bytes: wasm_bytes.ml test_bytes.ml | $(BUILD)
	cp wasm_bytes.ml test_bytes.ml $(BUILD)/
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -o test_bytes wasm_bytes.ml test_bytes.ml

$(BUILD)/test_runtime: $(BUILD)/blotc test_runtime.ml
	cp test_runtime.ml $(BUILD)/
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -o test_runtime base.cmx ox_model.cmx ox_numeric_literal.cmx ox_index.cmx test_runtime.ml

$(BUILD)/test_parallel: $(BUILD)/blotc test_parallel.ml
	cp test_parallel.ml $(BUILD)/
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -I +threads -o test_parallel unix.cmxa threads.cmxa native_parallel.cmx test_parallel.ml

$(BUILD)/test_domains: $(BUILD)/blotc test_domains.ml
	cp test_domains.ml $(BUILD)/
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -I +threads -o test_domains unix.cmxa threads.cmxa native_parallel.cmx test_domains.ml

test: all $(BUILD)/test_bytes $(BUILD)/test_runtime $(BUILD)/test_parallel $(if $(filter domains,$(PARALLEL)),$(BUILD)/test_domains)
	$(BUILD)/test_bytes
	$(BUILD)/test_runtime
	$(BUILD)/test_parallel $(PARALLEL)
	$(if $(filter domains,$(PARALLEL)),$(BUILD)/test_domains,true)
	python3 test_transport.py $(BUILD)/blotc

clean:
	rm -rf $(BUILD)
