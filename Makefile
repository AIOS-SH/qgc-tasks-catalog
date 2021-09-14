ENV_NAME     ?= dev
NAMESPACE    ?= qgc-$(ENV_NAME)

# Set this variable to restore database
ARCHIVE_TO_RESTORE ?=

HELM_NS_OPTS ?= --namespace $(NAMESPACE) $(shell $(HELM_INSTALL) && echo --create-namespace)
HELM_OPTIONS ?=
HELM_INSTALL ?= false
HELM_UPGRADE ?= $(shell $(HELM_INSTALL) || echo diff) upgrade --install $(shell $(HELM_INSTALL) || echo -C 5)

deploy-tasks:
	helm $(HELM_UPGRADE) tasks charts/tasks --namespace $(NAMESPACE)

deploy-tasks-everywhere:
	for ns in `kubectl get ns -l qgc/applicationId -o custom-columns=NAME:.metadata.name --no-headers`; \
	do \
		echo "Deploying in $$ns ..." && \
		helm $(HELM_UPGRADE) tasks charts/tasks --namespace $$ns || exit 1 ; \
		echo ; \
	done
