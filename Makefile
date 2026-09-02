.PHONY: check check-actions check-ci check-docs check-kubernetes check-schemas check-shell check-shellcheck check-template check-tests

ACTIONLINT_BIN ?= actionlint
EKSCTL_BIN ?= eksctl
KUBECONFORM_BIN ?= kubeconform
KUBERNETES_SCHEMA_COMMIT ?= 14355cdd490a43d21e05985668815a36a6f97da6
SHELLCHECK_BIN ?= shellcheck

check: check-docs check-shell check-template check-tests

check-ci: check check-schemas check-kubernetes check-actions check-shellcheck

check-docs:
	python3 scripts/check_docs.py

check-shell:
	bash -n scripts/preflight.sh scripts/render-cluster-config.sh scripts/verify-lab-ownership.sh tests/shell-scripts.bash

check-tests:
	bash tests/shell-scripts.bash

check-template:
	@AWS_REGION=us-east-1 \
		CLUSTER_NAME=eks-learning \
		EKS_VERSION=1.36 \
		PUBLIC_ACCESS_CIDR=203.0.113.10/32 \
		OWNER_TAG=ci \
		DELETE_AFTER=2099-01-01 \
		./scripts/render-cluster-config.sh | \
		python3 -c 'import sys; text = sys.stdin.read(); assert "__" not in text; assert "AmazonLinux2023" in text; assert '\''Owner: "ci"'\'' in text'
	@! AWS_REGION=us-east-1 \
		CLUSTER_NAME=eks-learning \
		EKS_VERSION=1.36 \
		PUBLIC_ACCESS_CIDR=999.0.0.1/32 \
		OWNER_TAG=ci \
		DELETE_AFTER=2099-01-01 \
		./scripts/render-cluster-config.sh >/dev/null 2>&1
	@! AWS_REGION=us-east-1 \
		CLUSTER_NAME=eks-learning \
		EKS_VERSION=1.36 \
		PUBLIC_ACCESS_CIDR=0.0.0.0/0 \
		OWNER_TAG=ci \
		DELETE_AFTER=2099-01-01 \
		./scripts/render-cluster-config.sh >/dev/null 2>&1
	@! AWS_REGION=us-east-1 \
		CLUSTER_NAME=eks-learning \
		EKS_VERSION=1.36 \
		PUBLIC_ACCESS_CIDR=203.0.113.10/32 \
		OWNER_TAG=ci \
		DELETE_AFTER=2099-02-30 \
		./scripts/render-cluster-config.sh >/dev/null 2>&1
	@AWS_REGION=us-east-1 \
		CLUSTER_NAME=true \
		EKS_VERSION=1.36 \
		PUBLIC_ACCESS_CIDR=203.0.113.10/32 \
		OWNER_TAG=ci \
		DELETE_AFTER=2099-01-01 \
		./scripts/render-cluster-config.sh | \
		python3 -c 'import sys; assert "name: \"true\"" in sys.stdin.read()'

check-schemas:
	python3 scripts/validate_schemas.py --eksctl "$(EKSCTL_BIN)"

check-kubernetes:
	@for version in 1.34.0 1.35.0 1.36.0; do \
		echo "Validando Kubernetes $$version"; \
		"$(KUBECONFORM_BIN)" \
			-strict \
			-summary \
			-kubernetes-version "$$version" \
			-schema-location "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/$(KUBERNETES_SCHEMA_COMMIT)/{{.NormalizedKubernetesVersion}}-standalone-strict/{{.ResourceKind}}.json" \
			examples/workloads/hello.yaml || exit 1; \
	done

check-actions:
	"$(ACTIONLINT_BIN)" -no-color

check-shellcheck:
	"$(SHELLCHECK_BIN)" scripts/preflight.sh scripts/render-cluster-config.sh scripts/verify-lab-ownership.sh tests/shell-scripts.bash
