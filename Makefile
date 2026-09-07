.DEFAULT_GOAL := help
.PHONY: help setup build run daemon overlay status pet switch test test-overlay lint format qa-console qa-render verify-assets
PYTHON := .venv/bin/python
CONFIGURATION ?= release
SWIFT := swift
QA_DIR ?= build/qa
PET ?= nara

help:
	@echo "UselessPet — Completely useless. Surprisingly good company."
	@echo "make setup        Install the locked Python environment using uv"
	@echo "make run          Build and run your desktop companion"
	@echo "make install-dev  Update and open /Applications/UselessPet Dev.app"
	@echo "make test         Run backend and local protocol tests"
	@echo "make test-overlay Run native view and renderer unit tests"
	@echo "make lint         Check Python code without changing files"
	@echo "make verify-assets Verify the distributed character files"

setup:
	uv sync --locked

build:
	$(SWIFT) build -c $(CONFIGURATION) --package-path overlay

run: build
	$(PYTHON) -m uselesspet run --overlay "$$($(SWIFT) build -c $(CONFIGURATION) --package-path overlay --show-bin-path)/UselessPet"

daemon:
	$(PYTHON) -m uselesspet daemon

overlay: build
	"$$($(SWIFT) build -c $(CONFIGURATION) --package-path overlay --show-bin-path)/UselessPet"

status:
	$(PYTHON) -m uselesspet status

pet:
	$(PYTHON) -m uselesspet pet

switch:
	$(PYTHON) -m uselesspet switch $(PET)

test:
	$(PYTHON) -m pytest tests -q

test-overlay:
	$(SWIFT) test --package-path overlay

lint:
	.venv/bin/ruff check backend tests scripts
	.venv/bin/ruff format --check backend tests scripts

format:
	.venv/bin/ruff check --fix backend tests scripts
	.venv/bin/ruff format backend tests scripts

qa-console: build
	USELESSPET_DUMP_CONSOLE="$(QA_DIR)/console" "$$($(SWIFT) build -c $(CONFIGURATION) --package-path overlay --show-bin-path)/UselessPet"

qa-render: build
	USELESSPET_QA_COMPANION="$(QA_DIR)/runtime" "$$($(SWIFT) build -c $(CONFIGURATION) --package-path overlay --show-bin-path)/UselessPet"

verify-assets:
	$(PYTHON) scripts/verify_assets.py

.PHONY: update-asset-manifest
update-asset-manifest:
	$(PYTHON) scripts/verify_assets.py --update

.PHONY: qa-mochi-face
qa-mochi-face: build
	USELESSPET_QA_MOCHI_FACE="$(QA_DIR)/mochi-face" "$$($(SWIFT) build -c $(CONFIGURATION) --package-path overlay --show-bin-path)/UselessPet"

.PHONY: qa-hybrid-face
qa-hybrid-face: build
	USELESSPET_QA_HYBRID_FACE="$(QA_DIR)/$(PET)-face" USELESSPET_QA_SPECIES="$(PET)" "$$($(SWIFT) build -c $(CONFIGURATION) --package-path overlay --show-bin-path)/UselessPet"

.PHONY: qa-roster-refinement
qa-roster-refinement:
	$(MAKE) qa-hybrid-face PET=pando
	$(MAKE) qa-hybrid-face PET=lumi
	$(MAKE) qa-render

.PHONY: package-dev install-dev verify-dev
APPLICATIONS_DIR ?= /Applications
package-dev: build verify-assets
	$(PYTHON) scripts/dev_app.py package --binary-dir "$$($(SWIFT) build -c $(CONFIGURATION) --package-path overlay --show-bin-path)"
	$(SWIFT)c scripts/dev_control.swift -o build/dev-app/dev-control

install-dev: package-dev
	$(PYTHON) scripts/dev_app.py install --applications-dir "$(APPLICATIONS_DIR)"

verify-dev:
	$(PYTHON) scripts/dev_app.py verify --app "$(APPLICATIONS_DIR)/UselessPet Dev.app"
