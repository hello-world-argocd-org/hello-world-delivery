CHART_NAME := springboot-app
KIND_CLUSTER := hw-test
K8S_VERSION := v1.33.2
NAMESPACE_DEV := dev
NAMESPACE_STAGE := stage
NAMESPACE_PROD := prod
SVC_PORT := 8080
LOCAL_PORT := 18080

# Expected responses
EXPECT_DEV := Shared value: [5] env value: [DEV]
EXPECT_STAGE := Shared value: [5] env value: [STAGE]
EXPECT_PROD := Shared value: [5] env value: [PROD]

.PHONY: all lint check-image-tag template kind-up kind-down install test-envs clean

all: lint check-image-tag template kind-up install test-envs kind-down

check-image-tag:
	@echo "==> Checking image.tag overrides in env values.yaml"
	@for env in dev stage prod; do \
	  file="envs/$$env/values.yaml"; \
	  echo "--> $$file"; \
	  if ! [ -f "$$file" ]; then \
	    echo "❌ Missing $$file"; \
	    exit 1; \
	  fi; \
	  tag=$$(yq e '.springboot-app.image.tag // ""' "$$file"); \
	  if [ -z "$$tag" ]; then \
	    echo "❌ Missing image.tag in $$file"; \
	    exit 1; \
	  fi; \
	done
	@echo "✅ image.tag check passed"

lint:
	@echo "==> Linting Helm chart"
	helm lint . -f envs/dev/values.yaml
	helm lint . -f envs/stage/values.yaml
	helm lint . -f envs/prod/values.yaml

template:
	@echo "==> Validating rendered manifests with kubeconform"
	helm repo add BASE_HELM_CHARTS https://hello-world-argocd-org.github.io/base-helm-charts/
	helm dependency build
	helm template $(CHART_NAME) . -f envs/dev/values.yaml | kubeconform -strict -ignore-missing-schemas
	helm template $(CHART_NAME) . -f envs/stage/values.yaml | kubeconform -strict -ignore-missing-schemas
	helm template $(CHART_NAME) . -f envs/prod/values.yaml | kubeconform -strict -ignore-missing-schemas

kind-up:
	@echo "==> Creating Kind cluster $(KIND_CLUSTER)"
	kind create cluster --name $(KIND_CLUSTER) --image kindest/node:$(K8S_VERSION)

kind-down:
	@echo "==> Deleting Kind cluster $(KIND_CLUSTER)"
	kind delete cluster --name $(KIND_CLUSTER)

install:
	@echo "==> Installing chart for dev, stage, prod"
	helm repo add BASE_HELM_CHARTS https://hello-world-argocd-org.github.io/base-helm-charts/
	helm dependency build
	helm install $(CHART_NAME)-dev . -n $(NAMESPACE_DEV) --create-namespace -f envs/dev/values.yaml
	helm install $(CHART_NAME)-stage . -n $(NAMESPACE_STAGE) --create-namespace -f envs/stage/values.yaml
	helm install $(CHART_NAME)-prod . -n $(NAMESPACE_PROD) --create-namespace -f envs/prod/values.yaml

test-envs:
	@echo "==> Testing endpoints"
	helm repo add BASE_HELM_CHARTS https://hello-world-argocd-org.github.io/base-helm-charts/
	helm dependency build
	$(MAKE) _test-env NAMESPACE=$(NAMESPACE_DEV) EXPECT="$(EXPECT_DEV)"
	$(MAKE) _test-env NAMESPACE=$(NAMESPACE_STAGE) EXPECT="$(EXPECT_STAGE)"
	$(MAKE) _test-env NAMESPACE=$(NAMESPACE_PROD) EXPECT="$(EXPECT_PROD)"

_test-env:
	@echo "--> Waiting for deployment in namespace $(NAMESPACE)"
	kubectl -n $(NAMESPACE) rollout status deploy/$(CHART_NAME) --timeout=180s

	@echo "--> Port-forwarding service in $(NAMESPACE)"
	SVC_NAME=$$(kubectl -n $(NAMESPACE) get svc -o jsonpath='{.items[0].metadata.name}'); \
	kubectl -n $(NAMESPACE) port-forward svc/$$SVC_NAME $(LOCAL_PORT):$(SVC_PORT) >/tmp/pf-$(NAMESPACE).log 2>&1 & \
	PF_PID=$$!; \
	sleep 3; \
	ACTUAL=$$(curl -fsS http://127.0.0.1:$(LOCAL_PORT)/ || true); \
	kill $$PF_PID || true; \
	wait $$PF_PID 2>/dev/null || true; \
	echo "Got: $$ACTUAL"; \
	if [ "$$ACTUAL" != "$(EXPECT)" ]; then \
	  echo "❌ Test failed for $(NAMESPACE)"; \
	  exit 1; \
	fi; \
	echo "✅ $(NAMESPACE) OK"

clean: kind-down
