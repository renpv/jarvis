# Makefile
#   make test         lint + testes bats (o mínimo antes de qualquer commit)
#   make ci           portão 1 completo, igual ao GitHub: test + actionlint + zizmor + gitleaks
#   make ferramentas  instala as ferramentas fixadas (ci/ferramentas.txt) em .ci-bin/
#   make hooks        ativa os hooks de ci/hooks (pre-commit e pre-push)
SHELL := /bin/bash
CI_BIN := $(CURDIR)/.ci-bin
export PATH := $(CI_BIN)/bin:$(PATH)
SCRIPTS := $(wildcard provision/*.sh) bin/jarvis bin/jarvis-expose bin/jarvis-peer bin/jarvis-backup \
           $(wildcard ci/*.sh) $(wildcard ci/hooks/*)

.PHONY: test lint unit ci ferramentas hooks
test: lint unit

lint:
	shellcheck -x $(SCRIPTS)
	@for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done

unit:
	bats tests

ci: test
	@for t in actionlint zizmor gitleaks; do \
	  command -v $$t >/dev/null || { echo "faltando: $$t — rode: make ferramentas"; exit 1; }; done
	actionlint
	zizmor --offline .
	gitleaks git --redact --no-banner .

ferramentas:
	ci/instalar-ferramentas.sh $(CI_BIN) shellcheck bats actionlint zizmor gitleaks

hooks:
	git config core.hooksPath ci/hooks
	@echo "hooks ativos: ci/hooks/pre-commit e ci/hooks/pre-push"
