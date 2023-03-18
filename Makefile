# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 E. K. Herman
#
# This centos build is based on our debian work at git.openelectronicslab.org
# https://git.openelectronicslab.org
#	/openelectronicslab/git.openelectronicslab.org/-/blob/master/Makefile
#
# Makefile cheat-sheet:
#
# $@ : target label
# $< : the first prerequisite after the colon
# $^ : all of the prerequisite files
# $* : wildcard matched part
#
# Setting Variables:
# https://www.gnu.org/software/make/manual/html_node/Setting.html
#
# Target-specific Variable syntax:
# https://www.gnu.org/software/make/manual/html_node/Target_002dspecific.html
#
# patsubst : $(patsubst pattern,replacement,text)
#       https://www.gnu.org/software/make/manual/html_node/Text-Functions.html

SHELL=/bin/bash

DISTRO_VERSION ?= 8.7
DISTRO_ISO_URL ?= https://download.rockylinux.org/pub/rocky/8/isos/x86_64/Rocky-8.7-x86_64-minimal.iso
KICKSTART_CFG ?= rocky-$(DISTRO_VERSION)-kickstart.cfg
DISTRO_ORIG_ISO ?= Rocky-8.7-x86_64-minimal.iso

ISOLINUX_CFG_PATCH ?= rocky-$(DISTRO_VERSION)-isolinux.cfg.patch
ISO_TARGET_VOLUME ?= Rocky-$(DISTRO_VERSION)-AutoInstall
ISO_TARGET ?= rocky-$(DISTRO_VERSION)-autoinstall.iso
TARGET_QCOW2 ?= basic-rocky-$(DISTRO_VERSION)-vm.qcow2

# set VM_HOSTNAME if not already set
VM_HOSTNAME ?= vm0
VM_PORT_SSH ?= 11022
VM_PORT_HTTP ?= 11080
VM_PORT_HTTPS ?= 11443

INITIAL_DISK_SIZE=20G
KVM_CORES=2
KVM_INSTALL_RAM=1G
KVM_RAM=8G

SSH_MAX_INIT_SECONDS=60
DELAY=0.1
RETRIES=$(shell echo "$(SSH_MAX_INIT_SECONDS)/$(DELAY)" | bc)

default: launch-base-vm

clean:
	rm -rf iso *-autoinstall.iso *.qcow2

spotless:
	git clean -dffx
	git submodule foreach --recursive git clean -dffx


$(DISTRO_ORIG_ISO):
	@echo "begin $@"
	wget $(DISTRO_ISO_URL) --output-document=$@
	ls -l $@
	@echo "SUCCESS $@"

vm_root_password:
	@echo "begin $@"
	touch vm_root_password
	chmod -v 600 vm_root_password
	cat /dev/urandom \
		| tr --delete --complement 'a-zA-Z0-9' \
		| fold --width=32 \
		| head --lines=1 \
		> vm_root_password
	ls -l vm_root_password
	@echo "SUCCESS $@"

iso/isolinux/ks/ks.cfg: $(DISTRO_ORIG_ISO) vm_root_password
	@echo "begin $@"
	mkdir -pv iso
	cd iso && 7z x ../$<
	patch -Np1 -i $(ISOLINUX_CFG_PATCH)
	mkdir -pv iso/isolinux/ks/
	cp -v $(KICKSTART_CFG) iso/isolinux/ks/ks.cfg
	sed -i -e"s/REPLACE_ROOT_PASSWORD/`cat vm_root_password | xargs`/g" \
		iso/isolinux/ks/ks.cfg
	sed -i -e"s/REPLACE_HOST_NAME/$(VM_HOSTNAME)/g" \
		iso/isolinux/ks/ks.cfg
	@echo "SUCCESS $@"

id_rsa_tmp:
	@echo "begin $@"
	ssh-keygen -b 4096 -t rsa -N "" -C "temporary-key" -f ./id_rsa_tmp
	ls -l id_rsa_tmp
	@echo "SUCCESS $@"

id_rsa_tmp.pub: id_rsa_tmp
	@echo "begin $@"
	ls -l id_rsa_tmp.pub
	@echo "SUCCESS $@"

id_rsa_host_tmp:
	@echo "begin $@"
	ssh-keygen -b 4096 -t rsa -N "" -C "temp-host-key" -f ./id_rsa_host_tmp
	ls -l id_rsa_host_tmp
	@echo "SUCCESS $@"

id_rsa_host_tmp.pub: id_rsa_host_tmp
	@echo "begin $@"
	ls -l id_rsa_host_tmp.pub
	@echo "SUCCESS $@"

iso/authorized_keys_tmp: iso/isolinux/ks/ks.cfg id_rsa_tmp.pub \
		id_rsa_host_tmp.pub id_rsa_host_tmp
	@echo "begin $@"
	cp -v ./id_rsa_tmp.pub		iso/authorized_keys_tmp
	cp -v ./id_rsa_host_tmp		iso/id_rsa_host_tmp
	cp -v ./id_rsa_host_tmp.pub	iso/id_rsa_host_tmp.pub
	ls -l iso/*_tmp*
	@echo "SUCCESS $@"

# generate the new iso install image
$(ISO_TARGET): iso/authorized_keys_tmp
	@echo "begin $@"
	genisoimage -o $@ -b isolinux/isolinux.bin -c isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table -J -R \
		-V "$(ISO_TARGET_VOLUME)" iso
	ls -l $(ISO_TARGET)
	@echo "SUCCESS $@"

$(TARGET_QCOW2): $(ISO_TARGET)
	@echo "begin $@"
	{ lsof -i:$(VM_PORT_SSH); if [ $$? -eq 0 ]; then \
		echo "port $(VM_PORT_SSH) not free"; false; fi; }
	qemu-img create -f qcow2 tmp.qcow2 $(INITIAL_DISK_SIZE)
	qemu-system-x86_64 -hda tmp.qcow2 -cdrom $(ISO_TARGET) \
		-m $(KVM_INSTALL_RAM) -smp $(KVM_CORES) \
		-machine type=q35,accel=kvm:tcg \
		-display none \
		-nic user,hostfwd=tcp:127.0.0.1:$(VM_PORT_SSH)-:22
	mv tmp.qcow2 $(TARGET_QCOW2)
	ls -l $(TARGET_QCOW2)
	@echo "SUCCESS $@"

launch-base-vm: $(TARGET_QCOW2)
	@echo "begin $@"
	{ lsof -i:$(VM_PORT_SSH); if [ $$? -eq 0 ]; then \
		echo "port $(VM_PORT_SSH) not free"; false; fi; }
	{ qemu-system-x86_64 -hda $(TARGET_QCOW2) \
		-m $(KVM_RAM) -smp $(KVM_CORES) \
		-machine type=q35,accel=kvm:tcg \
		-display none \
		-nic user,\
hostfwd=tcp:127.0.0.1:$(VM_PORT_HTTPS)-:443,\
hostfwd=tcp:127.0.0.1:$(VM_PORT_HTTP)-:80,\
hostfwd=tcp:127.0.0.1:$(VM_PORT_SSH)-:22 & \
		echo "$$!" > 'qemu.pid' ; }
	./retry.sh $(RETRIES) $(DELAY) \
		ssh -p$(VM_PORT_SSH) \
			-oNoHostAuthenticationForLocalhost=yes \
			root@127.0.0.1 \
			-i ./id_rsa_tmp \
			'/bin/true'
	echo "check the key matches the one we generated"
	ssh-keyscan -p$(VM_PORT_SSH) 127.0.0.1 \
		| grep `cat id_rsa_host_tmp.pub | cut -f2 -d' '`
	echo ssh -i ./id_rsa_tmp -p$(VM_PORT_SSH) \
		-oNoHostAuthenticationForLocalhost=yes \
		root@127.0.0.1
	@echo "SUCCESS $@"
	echo "$@ kvm running"

shutdown-kvm:
	@echo "begin $@"
	ssh -p$(VM_PORT_SSH) \
		-oNoHostAuthenticationForLocalhost=yes \
		root@127.0.0.1 \
		-i ./id_rsa_tmp \
		'shutdown -h -t 2 now & exit'
	{ while kill -0 `cat qemu.pid`; do \
		echo "wating for `cat qemu.pid`"; sleep 1; done }
	sleep 1
	echo "yay"
