SHELL := /bin/sh
.DEFAULT_GOAL := help

CLUSTER_NAME ?= platform
ARGOCD_NAMESPACE ?= argocd
ARGOCD_LOCAL_PORT ?= 8080
DEMO_HOST ?= demo.dev.localtest.me
DEMO_NAMESPACE ?= demo-dev

.PHONY: help up down status argocd-password port-forward lint validate demo set-repo

help: ## Show this help
	@echo "Targets:"
	@grep -hE '^[a-z][a-z-]*:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1m%-18s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Variables: CLUSTER_NAME=$(CLUSTER_NAME) DEMO_HOST=$(DEMO_HOST)"

up: ## Create the kind cluster, install Argo CD, apply the root Application
	@CLUSTER_NAME=$(CLUSTER_NAME) ./scripts/bootstrap.sh

down: ## Delete the kind cluster
	@CLUSTER_NAME=$(CLUSTER_NAME) ./scripts/teardown.sh

status: ## Show Argo CD Applications and platform pods
	@kubectl -n $(ARGOCD_NAMESPACE) get applications.argoproj.io
	@echo
	@for ns in $(ARGOCD_NAMESPACE) ingress-nginx cert-manager sealed-secrets $(DEMO_NAMESPACE); do \
		echo "--- $$ns"; \
		kubectl -n $$ns get pods --no-headers 2>/dev/null || echo "    (namespace not created yet)"; \
	done

argocd-password: ## Print the initial Argo CD admin password
	@kubectl -n $(ARGOCD_NAMESPACE) get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo

port-forward: ## Forward the Argo CD UI to localhost (ARGOCD_LOCAL_PORT)
	@echo "Argo CD UI: http://localhost:$(ARGOCD_LOCAL_PORT)  (user: admin, password: make argocd-password)"
	@kubectl -n $(ARGOCD_NAMESPACE) port-forward svc/argocd-server $(ARGOCD_LOCAL_PORT):80

lint: ## Run yamllint over the repository
	@./scripts/lint.sh

validate: ## Render every chart and overlay, then check them against the k8s schemas
	@./scripts/validate.sh

demo: ## Send a request to the demo workload through the ingress controller
	@DEMO_HOST=$(DEMO_HOST) DEMO_NAMESPACE=$(DEMO_NAMESPACE) ./scripts/demo.sh

set-repo: ## Point every Application at your fork: make set-repo REPO_URL=https://github.com/you/repo.git
	@REPO_URL=$(REPO_URL) ./scripts/set-repo.sh
