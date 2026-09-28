OCAMLOPT ?= ocamlopt
OCAMLFLAGS ?= -g -w -8-11-26-27
BUILD := _build
OCAML_MAJOR := $(shell $(OCAMLOPT) -version | cut -d. -f1)
PARALLEL := $(shell test "$(OCAML_MAJOR)" -ge 5 && echo domains || echo serial)
# OxCaml includes dependency extraction in the compiler. Stock OCaml 4 uses
# the ocamldep executable installed alongside ocamlopt.
OCAMLDEP ?= $(if $(filter 4,$(OCAML_MAJOR)),ocamldep,$(OCAMLOPT) -depend)
MODULES := $(shell cat core/modules.txt 2>/dev/null)
NATIVE := native_runtime native_parallel base $(MODULES) driver
TESTS := test_bytes test_runtime test_names test_parallel $(if $(filter domains,$(PARALLEL)),test_domains)
SOURCES := $(addprefix $(BUILD)/,$(addsuffix .ml,$(NATIVE) wasm_bytes $(TESTS) bench_names))
OBJECTS := $(addprefix $(BUILD)/,$(addsuffix .cmx,$(NATIVE)))
CONFIG := $(BUILD)/.configuration
COMPILE_FLAGS := $(OCAMLFLAGS) -I +threads $(if $(filter 4,$(OCAML_MAJOR)),,-I +unix)

.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.PHONY: all install bootstrap test test-build bench-names clean FORCE
all: $(BUILD)/blotc

# Explicit opt-in replacement at the existing native host path. The ordinary
# Bend build remains available; this target requires no Bend or JS compiler.
install: all
	@mkdir -p ../../generated/compiler
	@set -e; for destination in blotc-oxcaml blotc; do \
	  temporary=$$(mktemp ../../generated/compiler/.blotc-oxcaml-XXXXXX); \
	  trap 'rm -f "$$temporary"' EXIT; \
	  cp $(BUILD)/blotc "$$temporary"; chmod 755 "$$temporary"; \
	  mv "$$temporary" "../../generated/compiler/$$destination"; \
	done

bootstrap:
	python3 bootstrap/port.py

$(BUILD):
	mkdir -p $@

# Content comparison makes an unchanged build a no-op, while switching
# compilers, flags, or the selected worker backend invalidates every object.
$(CONFIG): FORCE | $(BUILD)
	@set -e; { command -v $(OCAMLOPT); $(OCAMLOPT) -config; \
	  printf '%s\n' '$(COMPILE_FLAGS)' '$(OCAMLDEP)' '$(PARALLEL)'; \
	  cksum "$$(command -v $(OCAMLOPT))"; } > $@.tmp
	@cmp -s $@.tmp $@ || mv $@.tmp $@
	@rm -f $@.tmp

$(BUILD)/native_parallel.ml: native_parallel_$(PARALLEL).ml $(CONFIG) Makefile | $(BUILD)
	@cmp -s $< $@ || cp $< $@

$(BUILD)/%.ml: %.ml | $(BUILD)
	cp $< $@

$(BUILD)/%.ml: core/%.ml | $(BUILD)
	cp $< $@

$(BUILD)/.depend: $(SOURCES) $(CONFIG) Makefile core/modules.txt
	cd $(BUILD) && $(OCAMLDEP) -native -one-line $(notdir $(SOURCES)) > .depend.raw
	sed -E 's@([A-Za-z_][A-Za-z_0-9]*\.cmx)@$(BUILD)/\1@g' $(BUILD)/.depend.raw > $@.tmp
	mv $@.tmp $@

# Do not build sources just to clean them or to materialize the initial port.
ifeq ($(filter clean bootstrap,$(MAKECMDGOALS)),)
include $(BUILD)/.depend
endif

# Each compilation publishes its interface, native metadata and object as one
# make rule. The dependency file orders consumers by their actual imports.
$(BUILD)/%.cmx $(BUILD)/%.cmi $(BUILD)/%.o &: $(BUILD)/%.ml $(CONFIG) Makefile
	cd $(BUILD) && $(OCAMLOPT) $(COMPILE_FLAGS) -c $*.ml

$(BUILD)/runtime_stubs.o: runtime_stubs.c $(CONFIG) Makefile
	cd $(BUILD) && $(OCAMLOPT) -c ../runtime_stubs.c

$(BUILD)/blotc: $(OBJECTS) $(OBJECTS:.cmx=.cmi) $(OBJECTS:.cmx=.o) $(BUILD)/runtime_stubs.o Makefile
	cd $(BUILD) && $(OCAMLOPT) $(COMPILE_FLAGS) -o blotc.tmp unix.cmxa threads.cmxa runtime_stubs.o $(notdir $(OBJECTS))
	mv $(BUILD)/blotc.tmp $@

$(BUILD)/test_bytes: $(BUILD)/wasm_bytes.cmx $(BUILD)/test_bytes.cmx
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -o test_bytes wasm_bytes.cmx test_bytes.cmx

$(BUILD)/test_runtime: $(addprefix $(BUILD)/,base.cmx ox_model.cmx ox_numeric_literal.cmx ox_index.cmx test_runtime.cmx)
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -o test_runtime $(notdir $^)

$(BUILD)/test_names: $(addprefix $(BUILD)/,base.cmx ox_model.cmx test_names.cmx)
	cd $(BUILD) && $(OCAMLOPT) $(OCAMLFLAGS) -o test_names $(notdir $^)

$(BUILD)/bench_names: $(addprefix $(BUILD)/,base.cmx ox_model.cmx bench_names.cmx)
	cd $(BUILD) && $(OCAMLOPT) $(COMPILE_FLAGS) -o bench_names unix.cmxa $(notdir $^)

bench-names: $(BUILD)/bench_names
	$(BUILD)/bench_names

$(BUILD)/test_parallel: $(BUILD)/native_parallel.cmx $(BUILD)/test_parallel.cmx
	cd $(BUILD) && $(OCAMLOPT) $(COMPILE_FLAGS) -o test_parallel unix.cmxa threads.cmxa $(notdir $^)

$(BUILD)/test_domains: $(BUILD)/native_parallel.cmx $(BUILD)/test_domains.cmx
	cd $(BUILD) && $(OCAMLOPT) $(COMPILE_FLAGS) -o test_domains unix.cmxa threads.cmxa $(notdir $^)

test: all $(addprefix $(BUILD)/,$(TESTS))
	$(BUILD)/test_bytes
	$(BUILD)/test_runtime
	$(BUILD)/test_names
	$(BUILD)/test_parallel $(PARALLEL)
	$(if $(filter domains,$(PARALLEL)),$(BUILD)/test_domains,true)
	python3 test_transport.py $(BUILD)/blotc

test-build:
	python3 test_build.py --compiler '$(OCAMLOPT)'

clean:
	rm -rf $(BUILD)

# Keep staged source files; they are required by the generated dependency graph.
.SECONDARY: $(SOURCES)
