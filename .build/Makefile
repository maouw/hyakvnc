SHELL := /bin/bash
.SHELLFLAGS := -e -O xpg_echo -o errtrace -o functrace -c
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables
MAKE := $(make)
DATETIME_FORMAT := %(%Y-%m-%d %H:%M:%S)T
.ONESHELL:
.SUFFIXES:
.DELETE_ON_ERROR:


#var_branch := $(shell git rev-parse --abbrev-ref HEAD)
var_branch := main
var_repo_url := $(shell git config --get remote.origin.url | sed -E 's/\.git$$//')
var_raw_script_url := $(shell echo $(var_repo_url) | sed -E 's/github\.com/raw.githubusercontent.com/; s/\/tree\/.*//')/$(var_branch)/hyakvnc
var_container_registry := "oras://ghcr.io/maouw"
var_hyakvnc_apptainer_repo := "https://github.com/maouw/hyakvnc_apptainer"
config.inc.md: ../hyakvnc
	$(shell sed -E '/^HYAKVNC_.*#\s*%%/!d; s/=.*(#\s*%%)/:/g; s/(^.)/- \1/g' $< > $@)

usage.inc.md: ../hyakvnc
	$(shell for x in create status show stop config install; do ../hyakvnc help "$$x" | sed -E '1 s/(.*)/\n### \1\n/; 2 s/^$$/```text/' | pr -e -t && echo '```'; done > $@)
	
../README.md: README.j2.md usage.inc.md config.inc.md
	jinja -D repo_url $(var_repo_url) -D container_registry $(var_container_registry) -D raw_script_url $(var_raw_script_url) -D hyakvnc_apptainer_repo var_hyakvnc_apptainer_repo $< > $@

.PHONY: README
README: ../README.md

.PHONY: clean
clean:
	rm -f ../README.md usage.inc.md config.inc.md

.DEFAULT_GOAL := README