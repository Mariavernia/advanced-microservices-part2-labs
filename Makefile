.PHONY: login preflight preflight-full test package local-up local-down p00-verify p00-clean

login:
	./scripts/login.sh

preflight:
	./scripts/preflight.sh

preflight-full:
	./scripts/preflight.sh --full

test:
	mvn test

package:
	mvn package

local-up:
	docker compose up --build

local-down:
	docker compose down

p00-verify:
	./labs/p00-kubernetes-survival-kit/scripts/verify.sh

p00-clean:
	./labs/p00-kubernetes-survival-kit/scripts/cleanup.sh

p01-deploy:
	bash labs/p01-complete-platform/scripts/deploy.sh

p01-verify:
	bash labs/p01-complete-platform/scripts/verify.sh

p01-clean:
	bash labs/p01-complete-platform/scripts/cleanup.sh
