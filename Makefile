MAKEAUXFLAGS?=-s
MAKE=make ${MAKEAUXFLAGS}

PWD=$(CURDIR)
UNAME := $(shell uname)

# The Juvix version compiler used to build the project.
VERSION?=0.3.3
JUVIXGLOBALFLAGS?=--internal-build-dir ./build/.juvix-build
JUVIXBIN?=juvix ${JUVIXGLOBALFLAGS}
JUVIXBINVERSION?=$(shell ${JUVIXBIN} --numeric-version)\
COMPILERSOURCES?=juvix-src
JUVIXFORMATFLAGS?=--in-place
JUVIXTYPECHECKFLAGS?=--only-errors

SRCDIR?=App
BUILDDIR?=build
CHECKEDDIR?=checked

SOURCES = $(shell find $(SRCDIR) -type f -name "*.juvix" -not -path '*/.*')
OUTPUTS = $(patsubst $(SRCDIR)/%.juvix,$(BUILDDIR)/%.o,$(SOURCES))
CHECKED = $(patsubst $(SRCDIR)/%.juvix,$(CHECKEDDIR)/$(SRCDIR)/%.juvix,$(SOURCES))

# ------------------------------------------------------------------------------

all: compile

# ------------------------------------------------------------------------------

deps/stdlib:
	@mkdir -p deps/
	@git clone https://github.com/anoma/juvix-stdlib.git deps/stdlib

# @git -C deps/stdlib checkout $(git tag --contains | tail -1)

.PHONY: deps
deps: deps/stdlib

# ------------------------------------------------------------------------------
# -- Check that the Juvix compiler version matches the documentation version --
# ----------------------------------------------------------------------------

.PHONY: juvix-sources
juvix-sources:
	@if [ ! -d ${COMPILERSOURCES} ]; then \
		git clone -b main https://github.com/anoma/juvix.git ${COMPILERSOURCES}; \
	fi
	@cd ${COMPILERSOURCES} && \
		git fetch --all && \
		if [ "${DEV}" = true ]; then \
			git checkout main > /dev/null 2>&1; \
		else \
			git checkout v${VERSION} > /dev/null 2>&1; \
		fi;

install-juvix: juvix-sources
	@cd ${COMPILERSOURCES} && ${MAKE} install

CHECKJUVIX:= $(shell command -v ${JUVIXBIN} 2> /dev/null)

.PHONY: juvix-bin
juvix-bin:
	@$(if $(CHECKJUVIX) , \
		, echo "[!] Juvix is not installed. Please install it and try again. Try make install-juvix")

# The numeric version of the Juvix compiler must match the
# version of the documentation specified in the VERSION file.
checkout-juvix: juvix-sources juvix-bin
	@if [ "${DEV}" != true ]; then \
		if [ "${JUVIXBINVERSION}" != "${VERSION}" ]; then \
			echo "[!] Juvix version ${JUVIXBINVERSION} does not match the documentation version $(VERSION)."; \
			exit 1; \
		fi; \
	fi

# ------------------------------------------------------------------------------
# Compile and typecheck
# ------------------------------------------------------------------------------

.PHONY: compile
compile: deps $(OUTPUTS)

.PHONY: compile
typecheck: deps $(CHECKED)

$(SRCDIR)/%.juvix: deps

$(BUILDDIR)/%.o: $(SRCDIR)/%.juvix
	@mkdir -p $(@D)
	@$(JUVIXBIN) compile $< -o $@

$(CHECKEDDIR)/$(SRCDIR)/%.juvix: $(SRCDIR)/%.juvix
	@echo "Checking $<"
	@echo "Moving $@"
	@mkdir -p $(@D)
	@$(JUVIXBIN) typecheck $< $(JUVIXTYPECHECKFLAGS) && \
		cp $< $@ && \
		juvix format $@ $(JUVIXFORMATFLAGS)

# TODO: add HTML output

# ------------------------------------------------------------------------------
# Project maintenance
# ------------------------------------------------------------------------------

.PHONY: clean-build
clean-build:
	@rm -rf build/

.PHONY: clean-deps
clean-deps:
	@rm -rf deps/

.PHONY: clean
clean: clean-deps clean-build

.PHONY: clean-juvix-build
clean-juvix-build:
	@find . -type d -name '.juvix-build' | xargs rm -rf

.PHONY: clean-hard
clean-hard: clean
	@git clean -fdx

.PHONY: format
format:
	@exit_codes=; \
		for file in $(SOURCES); do \
			dirname=$$(dirname "$$file"); \
			filename=$$(basename "$$file"); \
			cd $$dirname && \
				if [ -z "$(DEBUG)" ]; then \
					${JUVIXBIN} format $(JUVIXFORMATFLAGS) "$$filename"; \
				else \
					${JUVIXBIN} format $(JUVIXFORMATFLAGS) "$$filename" > /dev/null 2>&1; \
				fi; \
			exit_code=$$?; \
			if [ $$exit_code -eq 0 ]; then \
				echo "[OK] $$file"; \
				exit_codes+=0; \
			elif [[ "$$file" =~ ^\./tests/ ]]; then \
				echo "[-] $$file"; \
				exit_codes+=0; \
			else \
				exit_codes+=1; \
				echo "[ERROR] $$file"; \
			fi; \
			cd - > /dev/null; \
			done; \
		echo "$$exit_codes" | grep -q '1' && exit 1 || exit 0

.PHONY: check-format
check-format:
	@JUVIXFORMATFLAGS=--check	${MAKE} format

JUVIXEXAMPLEFILES=$(shell find ./examples \
	-type d \( -name ".juvix-build" \) -prune -o  \
	-type f -name "*.juvix" -print)

# ------------------------------------------------------------------------------


PRECOMMIT := $(shell command -v pre-commit 2> /dev/null)

.PHONY : install-pre-commit
install-pre-commit :
	@$(if $(PRECOMMIT),, pip install pre-commit)

.PHONY : pre-commit
pre-commit :
	@pre-commit run --all-files
