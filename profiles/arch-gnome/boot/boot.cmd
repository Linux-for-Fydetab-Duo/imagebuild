# u-boot boot script. Compiled to boot.scr by stages/03-image.sh:
#   mkimage -A arm64 -T script -C none -d boot.cmd boot.scr
# and installed to /boot/boot.scr in the rootfs.
#
# rootpart MUST match the partition layout in image.conf (root is partition 2).
# The kernel/initramfs/dtb names MUST match what the linux-fydetab package
# installs; 02-customize.sh asserts all four exist before the image is assembled.

# NOTE the underscore: the linux-v6.12 branch names the device tree
# rk3588s-fydetab_duo.dts (the FydeOS convention). The 6.1-era kernel and the
# old released boot.scr used rk3588s-fydetab-duo.dtb with a hyphen -- copying
# that name here means u-boot finds no dtb and the boot stops.
setenv rootpart 2
setenv fdtfile /boot/dtbs/rockchip/rk3588s-fydetab_duo.dtb
setenv linux_image /boot/vmlinuz-linux-fydetab
setenv initrd /boot/initramfs-linux-fydetab.img
part uuid ${devtype} ${devnum}:${rootpart} root_uuid
setenv bootargs rootfstype=ext4 rootwait rw root=PARTUUID=${root_uuid} console=ttyFIQ0,1500000n8 console=tty1 console=both init=/sbin/init
load ${devtype} ${devnum}:${rootpart} ${kernel_addr_c} ${linux_image}
load ${devtype} ${devnum}:${rootpart} ${fdt_addr_r} ${fdtfile}
load ${devtype} ${devnum}:${rootpart} ${ramdisk_addr_r} ${initrd}
booti ${kernel_addr_c} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
