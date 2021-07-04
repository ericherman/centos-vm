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

CENTOS_ORIG_ISO=CentOS-8.3.2011-x86_64-minimal.iso
CENTOS_MIRROR_BASE=http://linux-mirrors.fnal.gov/linux/centos
CENTOS_ISO_URL=$(CENTOS_MIRROR_BASE)/8.3.2011/isos/x86_64/$(CENTOS_ORIG_ISO)

# set VM_HOSTNAME if not already set
VM_HOSTNAME ?= vm0.example.org
VM_PORT_SSH ?= 11022
VM_PORT_HTTP ?= 11080
VM_PORT_HTTPS ?= 11443

INITIAL_DISK_SIZE=20G
KVM_CORES=2
KVM_INSTALL_RAM=1G
KVM_RAM=8G

ISO_TARGET=centos-8.3-autoinstall.iso

SSH_MAX_INIT_SECONDS=60
DELAY=0.1
RETRIES=$(shell echo "$(SSH_MAX_INIT_SECONDS)/$(DELAY)" | bc)

default: launch-base-vm

clean:
	rm -rf iso $(ISO_TARGET) *.qcow2

spotless:
	git clean -dffx
	git submodule foreach --recursive git clean -dffx


$(CENTOS_ORIG_ISO):
	wget $(CENTOS_ISO_URL)
	ls -l $@

vm_root_password:
	cat /dev/urandom \
		| tr --delete --complement 'a-zA-Z0-9' \
		| fold --width=32 \
		| head --lines=1 \
		> vm_root_password

iso/isolinux/ks/ks.cfg: $(CENTOS_ORIG_ISO) vm_root_password
	mkdir -pv iso
	cd iso && 7z x ../$<
	patch -Np1 -i isolinux.cfg.patch
	mkdir -pv iso/isolinux/ks/
	cp -v centos-8.3-kickstart.cfg iso/isolinux/ks/ks.cfg
	sed -i -e"s/ROOT_PASSWORD/`cat vm_root_password | xargs`/g" \
		iso/isolinux/ks/ks.cfg
	sed -i -e"s/ROOT_PASSWORD/$(VM_HOSTNAME)/g" \
		iso/isolinux/ks/ks.cfg

id_rsa_tmp:
	ssh-keygen -b 4096 -t rsa -N "" -C "temporary-key" -f ./id_rsa_tmp

id_rsa_tmp.pub: id_rsa_tmp

id_rsa_host_tmp:
	ssh-keygen -b 4096 -t rsa -N "" -C "temp-host-key" -f ./id_rsa_host_tmp

id_rsa_host_tmp.pub: id_rsa_host_tmp

iso/authorized_keys: iso/isolinux/ks/ks.cfg id_rsa_tmp.pub \
		id_rsa_host_tmp.pub id_rsa_host_tmp
	cp -v ./id_rsa_tmp.pub iso/authorized_keys
	cp -v ./id_rsa_host_tmp.pub iso/id_rsa_host_tmp.pub
	cp -v ./id_rsa_host_tmp iso/id_rsa_host_tmp

# generate the new iso install image
$(ISO_TARGET): iso/authorized_keys
	genisoimage -o $@ -b isolinux/isolinux.bin -c isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table -J -R \
		-V "CentOS-8.3-AutoInstall" iso

basic-centos-8.3-vm.qcow2: $(ISO_TARGET)
	{ lsof -i:$(VM_PORT_SSH); if [ $$? -eq 0 ]; then \
		echo "port $(VM_PORT_SSH) not free"; false; fi; }
	qemu-img create -f qcow2 tmp.qcow2 $(INITIAL_DISK_SIZE)
	# qemu-system-x86_64 -hda tmp.qcow2 -cdrom $(ISO_TARGET) \
	#	-m $(KVM_INSTALL_RAM) -smp $(KVM_CORES) \
	#	-machine type=pc,accel=kvm \
	#	-display none \
	#	-nic user,hostfwd=tcp:127.0.0.1:$(VM_PORT_SSH)-:22
	@echo
	@echo "====================================="
	@echo "Something is broken, connect with VNC"
	@echo "====================================="
	@echo
	qemu-system-x86_64 -hda tmp.qcow2 -cdrom $(ISO_TARGET) \
		-m $(KVM_INSTALL_RAM) -smp $(KVM_CORES) \
		-machine type=pc,accel=kvm \
		-nic user,hostfwd=tcp:127.0.0.1:$(VM_PORT_SSH)-:22
	mv tmp.qcow2 $@

launch-base-vm: basic-centos-8.3-vm.qcow2
	{ lsof -i:$(VM_PORT_SSH); if [ $$? -eq 0 ]; then \
		echo "port $(VM_PORT_SSH) not free"; false; fi; }
	{ qemu-system-x86_64 -hda $< \
		-m $(KVM_RAM) -smp $(KVM_CORES) -machine type=pc,accel=kvm \
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
	echo "$@ kvm running"

shutdown-kvm:
	ssh -p$(VM_PORT_SSH) \
		-oNoHostAuthenticationForLocalhost=yes \
		root@127.0.0.1 \
		-i ./id_rsa_tmp \
		'shutdown -h -t 2 now & exit'
	{ while kill -0 `cat qemu.pid`; do \
		echo "wating for `cat qemu.pid`"; sleep 1; done }
	sleep 1
	echo "yay"
