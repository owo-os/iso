CONF ?= macro
WIDTH ?= 32
BUSYOPTIONS ?= CPPFLAGS=-m$(WIDTH) LDFLAGS=-m$(WIDTH)

linconfigs := $(wildcard conf/*/configs/*)
busyconfigs := $(wildcard conf/busybox/*)

owo.iso: newroot newroot/boot/vmlinuz ## create final iso
	mkisofs -o owo.iso -b isolinux.bin -no-pad -no-emul-boot -boot-load-size 4 -boot-info-table newroot

ramfs.zst: root/bin/busybox ## create initramfs
	find root -printf "%P\0" | cpio --create --null --format newc -D root | zstd -19 > ramfs.zst

newroot/boot/vmlinuz: linux/vmlinux ## install linux to iso root
	cd linux && make install INSTALL_PATH=../newroot/boot
	rm -f newroot/boot/System.* newroot/boot/vmlinuz.old

newroot: ramfs.zst isolinux.cfg ## create contents of iso
	mkdir -p newroot/boot
	ln -f ramfs.zst newroot/boot
	ln -f isolinux.cfg newroot
	cp /usr/lib/syslinux/bios/isolinux.bin newroot
	cp /usr/lib/syslinux/bios/ldlinux.c32 newroot

root/bin/busybox: busybox/busybox ## install busybox to iso root
	mkdir -p root/bin root/proc root/dev
	ln -f busybox/busybox root/bin
	cd root/bin && ./busybox --list | grep -v busybox | xargs -n1 ln -sf busybox

busybox/.config: $(busyconfigs) ## reset busybox config
	ln -sf ../conf/busybox/$(CONF) busybox/.config

busybox/busybox: busybox busybox/.config
	cd busybox && $(BUSYOPTIONS) make -j"$(shell nproc)" $(BUSYFLAGS)

linux/.config: $(linconfigs) ## reset linux config
	cp -r conf/* linux/arch
	cd linux && make tinyconfig
	cd linux && make owo$(WIDTH)$(CONF).config

linux/vmlinux: linux linux/.config
	cd linux && make -j"$(shell nproc)"

satiate: ## trick make into not rebuilding deps
	touch linux/vmlinux busybox/busybox

busybox: ## download busybox source
	git clone -b 1_36_stable --depth 1 https://git.busybox.net/busybox/ busybox

linux: ## download linux source
	git clone -b v6.6 --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git linux

clean:
	rm -rf newroot root/bin
	rm -f ramfs.zst owo.iso linux/.config linux/vmlinux busybox/.config

distclean: clean ## also clean dependency build artifacts
	cd busybox && make distclean
	cd linux && make distclean

help:
	@sed -n 's/^\([[:alnum:]_\/\.-]\+\):[^#]*\(## \(.*\)\)\{0,1\}/\1|\3/p' \
		${MAKEFILE_LIST} | column -tl2 -s '|'
