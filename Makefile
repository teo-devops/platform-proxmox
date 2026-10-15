# platform-proxmox — de servidores sin instalar a un cluster Proxmox VE sano.
# `make` a secas enseña la ayuda. Casi todo pide ENV=<entorno> (inventory/<entorno>/).
# Referencia: docs/README.md

ENV ?=
INV := inventory/$(ENV)
EXAMPLES := 2-nodos 3-nodos 5-nodos
# Contraseña de ansible-vault: VAULT_PASS_FILE=<fichero> o, por defecto, se pregunta.
VAULT := $(if $(VAULT_PASS_FILE),--vault-password-file $(VAULT_PASS_FILE),--ask-vault-pass)
export ANSIBLE_CONFIG := $(CURDIR)/ansible.cfg
# Verificacion estricta contra el known_hosts del entorno (make known-hosts).
SSH_ARGS := -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$(CURDIR)/$(INV)/known_hosts
# ARGS: lo que se pasa tal cual a ansible-playbook (p. ej. ARGS="--tags network --limit pve2").
PLAY := ANSIBLE_SSH_ARGS="$(SSH_ARGS)" ansible-playbook -i $(INV) $(VAULT) ansible/playbooks/site.yml $(ARGS)

.DEFAULT_GOAL := help
.PHONY: help new check answers iso known-hosts preflight plan apply validate handoff lint test golden need-env

help:
	@echo "platform-proxmox — instala y configura un cluster Proxmox VE de 1 a N nodos"
	@echo
	@echo "PREPARAR  (docs/inventario.md)"
	@echo "  make new ENV=x FROM=2-nodos   crea inventory/x desde un ejemplo (2-nodos, 3-nodos, 5-nodos)"
	@echo "  make check ENV=x              valida el inventario: esquema y coherencia (sin conectar)"
	@echo
	@echo "INSTALAR PROXMOX  (docs/instalacion.md)"
	@echo "  make answers ENV=x            answer.toml de cada nodo en build/x/answers/"
	@echo "  make iso ENV=x NODE=n ISO=f   ISO desatendida del nodo n (USB o BMC)"
	@echo "  install/grub-oneshot.sh       alternativa sin USB ni BMC con medios (ver docs)"
	@echo "  bmc/ipmi.sh x n status|...    encendido, arranque y consola por IPMI"
	@echo
	@echo "CONFIGURAR  (docs/postinstalacion.md)"
	@echo "  make known-hosts ENV=x        claves de host de los nodos (TOFU; compruebalas)"
	@echo "  make preflight ENV=x          ¿los nodos son lo que dice el inventario?"
	@echo "  make plan ENV=x               lo que cambiaria (--check --diff); no toca nada"
	@echo "  make apply ENV=x              repos, ZFS, red, cluster, QDevice, accesos, copias"
	@echo "  make validate ENV=x           quorum, ZFS, red, repos y servicios"
	@echo "  make handoff ENV=x            bloque proxmox: para el platform.yaml de pve-platform-iac"
	@echo
	@echo "DESARROLLO"
	@echo "  make lint                     yamllint, ansible-lint, shellcheck, esquemas"
	@echo "  make test                     genera los ejemplos y los compara con tests/golden/"
	@echo "  make golden                   actualiza tests/golden/ (revisa el diff antes del commit)"
	@echo
	@echo "Contraseña del vault: VAULT_PASS_FILE=<fichero>, o te la pregunta."

need-env:
	@test -n "$(ENV)" || { echo "Falta ENV=<entorno> (inventory/<entorno>/)"; exit 1; }
	@test -d "$(INV)" || { echo "No existe $(INV). make new ENV=$(ENV) FROM=2-nodos"; exit 1; }

new:
	@test -n "$(ENV)" -a -n "$(FROM)" || { echo "make new ENV=<entorno> FROM=<2-nodos|3-nodos|5-nodos>"; exit 1; }
	@test ! -e "$(INV)" || { echo "$(INV) ya existe"; exit 1; }
	@mkdir -p inventory && cp -r examples/$(FROM) $(INV)
	@echo "✓ $(INV) creado desde examples/$(FROM)."
	@echo "  1. Edita $(INV)/hosts.yml y $(INV)/group_vars/all/main.yml (docs/inventario.md)"
	@echo "  2. Pon tus secretos en $(INV)/group_vars/all/vault.yml y cifralo:"
	@echo "       ansible-vault encrypt $(INV)/group_vars/all/vault.yml"
	@echo "  3. make check ENV=$(ENV)"

check: need-env
	check-jsonschema --schemafile schema/hosts.schema.json $(INV)/hosts.yml
	check-jsonschema --schemafile schema/vars.schema.json $(INV)/group_vars/all/main.yml
	ansible-playbook -i $(INV) $(VAULT) ansible/playbooks/render.yml -e render_env=$(ENV) >/dev/null
	@echo "✓ Inventario $(ENV) correcto (esquema y coherencia). Ficheros en build/$(ENV)/"

answers: check
	@ls build/$(ENV)/answers/

iso: need-env
	@test -n "$(NODE)" -a -n "$(ISO)" || { echo "make iso ENV=x NODE=<nodo> ISO=<proxmox-ve_*.iso>"; exit 1; }
	@test -f build/$(ENV)/answers/$(NODE).toml || $(MAKE) --no-print-directory answers ENV=$(ENV)
	install/make-iso.sh build/$(ENV)/answers/$(NODE).toml $(ISO) build/$(ENV)/$(NODE)-auto.iso

known-hosts: need-env
	scripts/known-hosts.sh $(ENV)

preflight: need-env
	$(PLAY) --tags preflight

plan: need-env
	$(PLAY) --check --diff

apply: need-env
	$(PLAY)

validate: need-env
	$(PLAY) --tags validate

handoff: need-env
	ansible-playbook -i $(INV) $(VAULT) ansible/playbooks/handoff.yml -e render_env=$(ENV)
	@cat build/$(ENV)/platform.yaml-proxmox.yaml

lint:
	yamllint -c .yamllint.yaml .
	ansible-lint ansible/
	shellcheck -S warning install/*.sh bmc/*.sh scripts/*.sh
	python3 scripts/check-docs-links.py
	@for e in $(EXAMPLES); do \
	  check-jsonschema --schemafile schema/hosts.schema.json examples/$$e/hosts.yml && \
	  check-jsonschema --schemafile schema/vars.schema.json examples/$$e/group_vars/all/main.yml || exit 1; \
	  ansible-playbook -i examples/$$e ansible/playbooks/site.yml --syntax-check >/dev/null || exit 1; \
	done
	@echo "✓ lint"

test:
	@for e in $(EXAMPLES); do \
	  ansible-playbook -i examples/$$e ansible/playbooks/render.yml -e render_env=$$e >/dev/null || exit 1; \
	  diff -ru tests/golden/$$e build/$$e || { echo "✗ $$e difiere de tests/golden (si es a proposito: make golden)"; exit 1; }; \
	done
	@echo "✓ Ejemplos iguales a tests/golden/"

golden:
	@for e in $(EXAMPLES); do \
	  ansible-playbook -i examples/$$e ansible/playbooks/render.yml -e render_env=$$e >/dev/null || exit 1; \
	  rm -rf tests/golden/$$e && mkdir -p tests/golden/$$e && cp -r build/$$e/answers build/$$e/interfaces tests/golden/$$e/; \
	done
	@echo "✓ tests/golden/ actualizado: revisa git diff"
