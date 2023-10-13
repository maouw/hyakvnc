SHELL := /bin/bash
.SHELLFLAGS := -e -O xpg_echo -o errtrace -o functrace -c
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables
MAKE := $(make)
DATETIME_FORMAT := %(%Y-%m-%d %H:%M:%S)T
.ONESHELL:
.SUFFIXES:
.DELETE_ON_ERROR:



config.inc.md: ../hyakvnc
	@ sed -E '/HYAKVNC_.*#\s*%%/!d; s/=.*(#\s*%%)/:/g' $< > $@



usage.inc.md: ../hyakvnc
	@ $(shell for x in create status show stop config install; do ../hyakvnc help "$$x" | sed -E '1 s/(.*)/\n### \1\n/; 2 s/^$$/```text/' | pr -e -t && echo '```'; done > $@)
	
README.md: README.md.j2 usage.inc.md config.inc.md
	@ jinja $< > $@

DEFAULT_GOAL := README.md
