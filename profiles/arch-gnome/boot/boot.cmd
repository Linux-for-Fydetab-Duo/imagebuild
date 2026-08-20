# u-boot boot script. Compiled to boot.scr by stages/mk-rk-script.py (the
# rockchip script dialect, not plain mkimage) and installed into the ESP.
#
# bootpart and rootpart MUST match the partition layout in image.conf: the ESP
# is partition 2 and carries kernel, initramfs, dtb and this script at its
# filesystem root (that root is /boot once Linux mounts it), the root
# filesystem is partition 3. The kernel/initramfs/dtb names MUST match what the
# linux-fydetab package installs; 02-customize.sh asserts they exist before the
# image is assembled. Comments are dropped at compile time; they are for humans.
setenv bootpart 2
setenv rootpart 3
# NOTE the underscore: the linux-v6.12 branch names the device tree
# rk3588s-fydetab_duo.dts (the FydeOS convention). The 6.1-era kernel and the
# old released boot.scr used rk3588s-fydetab-duo.dtb with a hyphen -- copying
# that name here means u-boot finds no dtb and the boot stops.
setenv fdtfile /dtbs/rockchip/rk3588s-fydetab_duo.dtb
setenv linux_image /vmlinuz-linux-fydetab
setenv initrd /initramfs-linux-fydetab.img
part uuid ${devtype} ${devnum}:${rootpart} root_uuid
# Console order matters: /dev/console binds to the LAST console= token, and
# u-boot merges the kernel DTS /chosen bootargs on top (DTB wins duplicates),
# so the DTS must not carry loglevel/console overrides. tty1 last keeps boot
# status on the panel; quiet+loglevel=3 hides kernel chatter (vendor dhd wifi
# logs info at ERROR level) while systemd.show_status keeps per-unit lines.
setenv bootargs rootfstype=ext4 rootwait rw root=PARTUUID=${root_uuid} console=ttyFIQ0,1500000n8 console=tty1 init=/sbin/init quiet loglevel=3 systemd.show_status=true rd.udev.log_level=3 vt.global_cursor_default=0
load ${devtype} ${devnum}:${bootpart} ${kernel_addr_c} ${linux_image}
load ${devtype} ${devnum}:${bootpart} ${fdt_addr_r} ${fdtfile}
load ${devtype} ${devnum}:${bootpart} ${ramdisk_addr_r} ${initrd}
booti ${kernel_addr_c} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
