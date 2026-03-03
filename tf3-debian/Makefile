SHELL      := bash
ANSIBLE    ?= /Users/laird/Sync/ivenv/bin/ansible-playbook
KEY        := $(CURDIR)/debian_id_ed25519
VMS        := debian1 debian2 debian3
VM_PATTERN := $(shell echo "$(VMS)" | tr ' ' '|')

.DEFAULT_GOAL := help
.PHONY: help create apply bootstrap ansible list ssh destroy

help: ## show available targets
	@awk 'BEGIN{FS=":.*?## "} /^[a-zA-Z_-]+:.*?## /{printf "  %-12s %s\n",$$1,$$2}' $(MAKEFILE_LIST)

create: apply bootstrap ansible ## full lab: terraform apply + SSH bootstrap + ansible

apply: ## terraform init + apply (generates SSH key if absent)
	terraform init -input=false -upgrade=false
	terraform apply -auto-approve

bootstrap: ## install openssh and inject SSH key on each VM via incus exec
	@for vm in $(VMS); do \
	  echo "=== $$vm ==="; \
	  incus exec cluster:$$vm -- env DEBIAN_FRONTEND=noninteractive \
	    apt-get install -y openssh-server >/dev/null 2>&1; \
	  incus exec cluster:$$vm -- sh -c \
	    "mkdir -p /root/.ssh && chmod 700 /root/.ssh"; \
	  incus file push $(KEY).pub cluster:$$vm/root/.ssh/authorized_keys; \
	  incus exec cluster:$$vm -- sh -c \
	    "chmod 600 /root/.ssh/authorized_keys \
	     && passwd -d root \
	     && systemctl enable --now ssh >/dev/null 2>&1"; \
	  echo "  SSH ready"; \
	done

ansible: ## run ansible playbook
	$(ANSIBLE) -i ansible/inventory.ini ansible/playbook.yml

list: ## show running VMs and SSH commands
	@echo "=== VMs ==="
	@incus list cluster: --columns=n,s,4,l --format=compact 2>/dev/null \
	  | grep -E "^($(VM_PATTERN))" || echo "  none running"
	@echo ""
	@echo "=== SSH ==="
	@terraform output -json vm_ips 2>/dev/null \
	  | python3 -c "import sys,json; \
	    [print(f'  ssh -i $(KEY) root@{v}  # {k}') \
	     for k,v in sorted(json.load(sys.stdin).items())]" \
	  2>/dev/null || echo "  (run 'make create' first)"

ssh: ## SSH into a VM — usage: make ssh VM=debian1
	@test -n "$(VM)" || { echo "usage: make ssh VM=<name>"; exit 1; }
	@IP=$$(terraform output -json vm_ips 2>/dev/null \
	  | python3 -c "import sys,json; print(json.load(sys.stdin).get('$(VM)',''))" \
	  2>/dev/null); \
	test -n "$$IP" || { echo "VM '$(VM)' not found — run 'make create' first"; exit 1; }; \
	ssh -i $(KEY) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$$IP

destroy: ## destroy all VMs
	terraform destroy -auto-approve
