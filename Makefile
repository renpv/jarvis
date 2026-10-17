# Makefile — `make test` roda o lint (shellcheck) e os testes (bats).
SHELL := /bin/bash
SCRIPTS := $(wildcard provision/*.sh) bin/jarvis bin/jarvis-expose bin/jarvis-peer bin/jarvis-backup

.PHONY: test lint unit
test: lint unit

lint:
	shellcheck -x $(SCRIPTS)

unit:
	bats tests
