# Storage stack plan: split /boot, btrfs + snapper, opt-in LUKS

Status: Phases 0 and 1 implemented and device-verified 2026-08-20;
Phases 2-4 agreed, not started. Covers GitHub issues
#1 (Disk encryption) and #2 (snapshots / rollback / factory reset /
hibernation). Supersedes the "recoverable subset" half of the
filesystem feature gap entry in docs/omarchy-profile-plan.md (accepted
as-is 2026-08-18); the firmware-bound half stays out of scope here.

## Decisions (2026-08-20)

- Firmware-bound features are deferred: Limine boot-menu rollback,
  factory reset, hibernation, and any U-Boot upgrade / EDK2-rk3588
  UEFI move. They get their own tracking issue; see "Out of scope".
- The image ships plaintext; encryption happens on-device at first
  boot (in-place `cryptsetup reencrypt --encrypt`). Rationale: baking
  LUKS at build time would need loop devices + device-mapper in the
  build container, breaking the stage-03 no-loop/no-mount design
  (stages/03-image.sh:4-8) and stage-04's offset-based verification,
  and the key would have to exist at build time. On-device encryption
  keeps the pipeline untouched and the key is never anywhere but the
  device.
- Encryption is opt-in via the first-boot setup flow. The passphrase
  prompt lives in the initramfs, where only a physical keyboard works
  (keyboard dock or USB); forcing it would strand keyboard-less users.
- First-boot setup adopts upstream Omarchy provisioning now
  (omarchy-provision-owner: user, password, hostname, timezone), per
  the 2026-08-19 assessment in docs/omarchy-profile-plan.md:284-304.
  The encryption question is a separate small fydetab unit ordered
  after it, so the vendored omarchy package is not forked deeper.
- Scope narrowed 2026-08-20: omarchy is the only profile this effort
  builds and verifies. arch-gnome keeps the Phase 0 layout changes
  (the boot layer stays identical across profiles) but is otherwise
  out of scope from Phase 0 device verification onward.
- The btrfs subvolume layout mirrors upstream Omarchy exactly
  (2026-08-20): @/@home/@log/@pkg top-level, root mounted subvol=/@,
  noatime,compress=zstd mount options,
  .snapshots nested under @ — see "Target layout" for the measured
  sources and the rollback consequence (an @-swap restore helper
  instead of snapper rollback).
- /boot is a real ESP (FAT32, GPT type EF00), not ext4, so the future
  UEFI switch (EDK2-rk3588 or mainline U-Boot EFI_LOADER) needs no
  repartitioning — it only adds EFI binaries to an ESP that already
  carries kernel/initramfs/dtb. Verified in the vendor U-Boot blob:
  the FAT32 driver plus fatload/fatls are compiled in, boot.scr is
  loaded via the filesystem-agnostic generic `load`
  (boot_a_script env), and partition discovery keys on the GPT
  legacy_boot attribute, not the type GUID. Worst-case fallback if
  the blob dislikes type EF00: keep type 8300 and flip the GUID with
  sgdisk at UEFI-switch time (metadata-only, layout unchanged).

## What closes which issue

- Issue #1 closes when opt-in LUKS2 ships (Phases 0, 2, 3).
- Issue #2 closes when pre-update snapshots + CLI rollback ship
  (Phases 0, 1), with boot-menu rollback / factory reset / hibernation
  explicitly split off as firmware/kernel-bound follow-ups.

## Current state (verified 2026-08-19)

- GPT: p1 FW blob region (LBA 64..65535, no fs), p2 ext4 root holding
  /boot, legacy_boot attr on p2 (stages/03-image.sh:48-52; constants
  image.conf:29-35). No ESP, no separate /boot.
- Boot: compiled boot.scr (stages/mk-rk-script.py), rootpart and the
  whole kernel cmdline hardcoded in profiles/*/boot/boot.cmd:13-27.
- U-Boot blob (2017.09 vendor, firmware/PROVENANCE.md): has
  ext4load/fatload; **no btrfs, no EFI** (verified by strings over the
  gunzipped payload in uboot.img). `sysboot` help text absent, so the
  extlinux env boilerplate is likely not backed by a real command —
  the "extlinux entries per snapshot" middle path is presumed dead.
- Kernel linux-fydetab 6.12.43: DM_CRYPT=y, CRYPTO_XTS=y, AES=y
  already; BTRFS_FS **not set**, HIBERNATION **not set** (headers pkg
  .config; FydeOS twin config agrees on all four).
- mkinitcpio HOOKS=(base udev autodetect modconf kms keyboard keymap
  consolefont block filesystems fsck) — no encrypt/resume/btrfs
  (profiles/omarchy/overlay/etc/mkinitcpio.conf:66).
- First boot: only resizefs.service (grow p2 + resize2fs/btrfs branch,
  self-disables). No user provisioning; user `omarchy` uid 1001 is
  baked with SDDM autologin.
- Already shipped and inert: cryptsetup, btrfs-progs, and the omarchy
  scripts (omarchy-snapshot exits 127 without snapper; omarchy-update
  then continues without a snapshot).

## Target layout

```
p1  FW         LBA 64..65535, bootloader blobs (unchanged)
p2  ESP        FAT32, type EF00, 512 MiB, legacy_boot attr,
               mounted /boot
p3  ROOT       omarchy: btrfs (LUKS2 underneath when opted in)
               arch-gnome: ext4 (unchanged behavior, new slot)
```

btrfs subvolumes mirror upstream Omarchy exactly (decided 2026-08-20;
measured from upstream's own scripts and the omarchy-iso installer):
top-level `@` (/), `@home` (/home), `@log` (/var/log), `@pkg`
(/var/cache/pacman/pkg) — the installer's full set (omarchy-iso
configurator + orchestrator/phases_impl.py; factory-reset-finish
recreates only @home/@log, so @pkg is created at install, never
recreated) — with snapper's `.snapshots` and, if
hibernation ever lands, `swap` nested INSIDE `@` (snapper
create-config and omarchy-hibernation-setup:57-62 semantics). Root is
mounted with subvol=/@ exactly like upstream — omarchy-system-
factory-reset:62 hard-checks that option, so matching it keeps the
shipped-but-inert upstream tools usable later. Nested `.snapshots`
needs no fstab entry. Rollback consequently does NOT use `snapper
rollback` (that requires default-subvolume boot, which upstream does
not use either): upstream restores by swapping `@` (limine-snapper-
restore; omarchy-system-factory-reset-finish shows the same flow), so
Phase 1 ships a small fydetab restore helper that mirrors it — clone
the chosen snapshot to a new `@`, keep the old root as
`@omarchy-old-<ts>`, carry `.snapshots` across — CLI-only, no boot
menu on this firmware.

fstab (omarchy): root by fs UUID (unchanged by later encryption — the
fs keeps its UUID inside the mapper) with subvol=/@, plus /boot
(vfat, UUID=<serial>, fmask=0077,dmask=0077 — FAT has no POSIX
permissions, the umask is what keeps root-only files root-only),
/home (subvol=/@home), /var/log (subvol=/@log), /var/cache/pacman/pkg
(subvol=/@pkg). No /.snapshots entry (nested). All btrfs mounts use
noatime,compress=zstd — the official installer's option set; the
kernel cmdline carries only rootflags=subvol=/@ like upstream's, the
rest applies on the fstab remount.

Kernel cmdline: `root=PARTUUID=<p3>` stays even for encrypted
installs — the initramfs hook probes the device and remaps to
/dev/mapper/root when it finds crypto_LUKS, so ONE boot.scr serves
both cases and no on-device boot.scr regeneration is needed.

## Phase 0 — split /boot into an ESP (both profiles)

Prerequisite for both issues: U-Boot must load kernel/initramfs from a
plaintext partition once the root is btrfs or LUKS. Making it a real
ESP is the UEFI future-proofing decided above.

- stages/03-image.sh: three-partition sgdisk (p2 type EF00);
  legacy_boot attr moves to p2; build p2 with `mkfs.vfat -i <serial>`
  + mtools `mcopy -s` over the rootfs's /boot content (mount-free,
  like mke2fs -d) and p3 over the rootfs with /boot left as an empty
  mountpoint; root fs UUID + FAT serial chosen up-front; fstab gains
  the /boot vfat line.
- image.conf: new ESP_MIB=512, partition offset constants, ROOT_FS
  stays per-profile.
- Packages: dosfstools into both profiles' packages.list (fsck.vfat);
  mtools into the x86 builder container.
- boot.cmd: `bootpart=2` for the three `load`s (paths lose the /boot
  prefix: /vmlinuz-linux-fydetab, /initramfs-linux-fydetab.img,
  /dtbs/rockchip/rk3588s-fydetab_duo.dtb), `rootpart=3` for
  `part uuid`. Mind the DTS /chosen bootargs merge caveat
  (boot.cmd:18-22) when touching the cmdline.
- resizefs: now grows p3; rewrite the RPi-derived script (fixing its
  `[[ ]]` under `#!/bin/sh`) and make the partition-grow step tolerate
  "already at max" (needed by Phase 3).
- stages/04-publish.sh: assertions move (legacy_boot on p2, boot
  artifacts verified inside p2 via mtools at its offset, blob-region
  overlap check against p2 start).
- Docs in the same change (documented invariant changes): CLAUDE.md
  "Boot chain" section (legacy_boot now on the BOOT partition; root is
  p3), docs/build-internals.md partition section, README.
- Verify: build green with stage-04 passing (done 2026-08-20, both
  profiles); flash the omarchy image; U-Boot discovers boot.scr on
  the FAT32/EF00 p2 (the key new check — if the vendor blob skips
  EF00-typed partitions, fall back to type 8300 with FAT content and
  flip the GUID at UEFI-switch time); device boots from SD and eMMC
  images; kernel updates write to the vfat /boot; resizefs grows p3.
  Verified on device 2026-08-20 (SD boot): boot.scr found on the EF00
  partition, vfat /boot mounted, resizefs grew p3 and self-disabled.
  U-Boot also reads FAT markedly faster than its ext4 driver
  (~40 MB of kernel+initramfs in ~3.2 s). Still open: an eMMC-flash
  boot test, to ride along with Phase 1's device verification.

## Phase 1 — btrfs root + snapper (omarchy profile) → issue #2

- Kernel: CONFIG_BTRFS_FS=y as a PKGBUILD config fragment with its
  grep guard (pkgbuilds/linux-fydetab-6.12/PKGBUILD:61-65,117-129),
  built-in (not =m) so the root mount needs no module. Follow the
  kernel-change rule: local verify before any kernel-repo push.
- stages/03-image.sh: for ROOT_FS=btrfs, restructure the staged tree
  into @/, @home/, @log/, @pkg/ (moving /home, /var/log and
  /var/cache/pacman/pkg content) and build with `mkfs.btrfs --rootdir
  --subvol` (rw: each, plus rw:@/.snapshots for snapper), `-U` for
  the pre-written fstab, into a file dd'd at the p3 offset. Built
  with --shrink and the partition sized from the actual output:
  mkfs.btrfs's --rootdir estimator over-reserves (measured ~2.2x on
  the real tree) and GROWS the file rather than fail, so its result,
  not du, is authoritative. Consequence: the shrunk root has only
  chunk-tail free space until grown, so resizefs.service moves to
  early boot (sysinit, Before=basic.target) on this profile.
- boot.cmd: rootfstype=btrfs and rootflags=subvol=/@ (omarchy
  profile's copy).
- Restore helper: a fydetab script mirroring upstream's @-swap flow
  (limine-snapper-restore / omarchy-system-factory-reset-finish):
  mount subvolid=5, clone the chosen read-only snapshot to a new @,
  rename the running root to @omarchy-old-<ts>, move .snapshots
  across, reboot. CLI-only rollback.
- Snapper baked statically (no runtime create-config): overlay ships
  /etc/snapper/configs/root from upstream's template
  (omarchy checkout: default/snapper/root) and SNAPPER_CONFIGS="root";
  enable snapper-cleanup.timer, leave snapper-timeline.timer disabled
  (mirrors omarchy install/config/snapper.sh) — one enable mechanism
  only, per the services rule.
- Packaging: re-add `snapper` to the vendored omarchy PKGBUILD deps
  (limine, limine-*-sync/hook stay dropped) + record in
  OMARCHY-VENDOR.md; add snapper to profiles/omarchy/packages.list.
- Result: omarchy-snapshot works, omarchy-update takes pre-update
  snapshots, rollback is the fydetab restore helper + reboot
  (CLI-only; no boot menu on this firmware).
- Verify on device: snapshot created by omarchy-update; a real
  rollback drill via the helper (mutate → restore → reboot → state
  restored, /.snapshots carried across); resizefs btrfs branch grows
  the fs; eMMC-flash boot test (carried over from Phase 0).
  Verified 2026-08-20 (SD): exact upstream layout and mount options
  live, early resizefs grew p3 to the medium, omarchy-snapshot
  create works (no more 127), restore drill passed with snapshot
  history intact and a clean reboot. Still open: the eMMC boot test.

## Phase 2 — first-boot provisioning (upstream adoption)

Per docs/omarchy-profile-plan.md:284-304, now promoted from deferred
TODO to in-plan:

- Build with NO baked user: drop the omarchy passwd entry and SDDM
  autologin overlay; mirror `omarchy apply system
  --defer-provisioning` so hooks record group grants into
  provisioning/groups instead of usermod (also closes the /etc/group
  membership gap noted in feature-gaps Tier 3).
- Stage /var/lib/omarchy/provisioning/pending; install and enable
  omarchy-provision-owner.service and its companion units from
  upstream install/provisioning/.
- Ordering: provisioning owns tty1 before SDDM; resizefs is
  independent in this phase and keeps running as today.
- Pre-build checks: aarch64 omarchy package ships
  bin/omarchy-provision-owner + install/provisioning/; gum is in the
  image; the tty1 form needs a physical keyboard — document the
  keyboard-dock requirement in the README.
- Verify on device: full first-boot flow creates the owner user with
  recorded groups, SDDM posture matches upstream (autologin only where
  upstream grants it), second boot does not re-run provisioning.

## Phase 3 — opt-in LUKS2 encryption → issue #1

New unit `fydetab-encrypt-setup.service` (overlay), ordered
After=omarchy-provision-owner.service, gated by its own run-once
marker; a gum prompt on tty1: "Encrypt disk? (needs the keyboard at
every boot)". Decline → marker written, nothing else. Accept:

1. Collect passphrase (twice), shrink the mounted btrfs by 64 MiB
   (`btrfs filesystem resize -64M /` — online shrink, making room for
   the LUKS2 header), write the passphrase to
   /boot/fydetab-encrypt.key plus a flag file (root-only via the
   fmask=0077 /boot mount options — FAT has no file modes), reboot.
   (/boot is plaintext by design; the file is wiped right after use,
   and the disk it briefly sits on was plaintext anyway.)
2. Next boot, a custom mkinitcpio hook `fydetab-crypt` (overlay:
   etc/initcpio/{install,hooks}/fydetab-crypt, added to HOOKS before
   `filesystems`; install hook pulls in cryptsetup, sfdisk, partx):
   sees the flag on p2, runs `cryptsetup reencrypt --encrypt
   --reduce-device-size 64M` on p3 with progress on the console
   (minutes — the fs is still image-sized, ~SLACK_MIB over content,
   NOT yet grown; this ordering is why resizefs must not run first),
   wipes the staged key, then grows p3 with sfdisk/partx and
   `cryptsetup resize` while it still holds the passphrase.
3. Steady state, same hook: probe p3; if crypto_LUKS, `cryptsetup
   open` (console passphrase prompt, few retries) and remap
   root=/dev/mapper/root; if plaintext, do nothing. fstab needs no
   variant — the fs UUID is unchanged.
4. resizefs: ConditionPathExists=!/boot/fydetab-encrypt.key so it
   skips the boot where encryption is pending (a skipped unit stays
   enabled); afterwards its partition-grow no-ops and only the
   fs-level grow runs.

SDDM/auth posture on encrypted installs follows upstream: the LUKS
prompt is the auth boundary (provision-owner keeps autologin there).

Verify on device: opt-out path boots and resizes as before; opt-in
path encrypts, prompts, boots, resizes; wrong-passphrase retry;
power-cut during reencrypt (LUKS2 reencryption is designed resumable —
verify the hook resumes, else document "reflash" as first-boot
recovery, which loses nothing since no user data exists yet).

## Phase 4 — docs + issue closure

- README: encryption opt-in + keyboard requirement; snapshots/CLI
  rollback; updated limitations list.
- docs/omarchy-feature-gaps.md: LUKS/autologin posture and snapshot
  entries updated; docs/omarchy-profile-plan.md: mark the superseded
  entries with a pointer here.
- GitHub: comment plan + close #1 and #2 per "What closes which
  issue"; open a new tracking issue for the firmware/UEFI route
  (mainline U-Boot EFI_LOADER vs EDK2-rk3588, per
  docs/omarchy-profile-plan.md:271-282) carrying boot-menu rollback
  and factory reset; note hibernation separately (kernel
  HIBERNATION=y rebuild + non-zram swap + resume args need on-device
  boot.scr regeneration; RK3588 BSP suspend is the risk — FydeOS's
  own config ships it off).

## Assumptions to verify at implementation time

- The vendor U-Boot's `part list -bootable` accepts the legacy_boot
  attribute on an EF00-typed partition (expected — the attribute
  check is type-independent; fatload/FAT32 driver and the generic
  `load` path are confirmed in the blob's strings). Fallback: type
  8300 now, GUID flip later.
- `mkfs.btrfs --rootdir --subvol` in the x86 build container's
  btrfs-progs can create the nested @/.snapshots subvolume (fallback:
  create it via a first-boot oneshot before snapper's first use).
- The @-swap restore helper round-trips on the real device (drill in
  Phase 1: restore, reboot, .snapshots intact) — modeled on upstream
  but running without Limine's boot-a-snapshot step.
- LUKS2 reencrypt crash-resume from our initramfs hook.
- qemu-emulated mkinitcpio builds the custom hook + extra binaries
  within reasonable initramfs size (Mali firmware already rides in
  it).
- Upstream omarchy-provision-owner runs unmodified on aarch64 with a
  plaintext root (its LUKS re-key step self-gates and must no-op).

## Sequencing rule

One phase at a time: implement → build → flash → verify on device →
commit, before the next (kernel btrfs change additionally follows the
CLAUDE.md kernel verify-before-push rule). Every phase implementation
starts from the official Omarchy implementation (local checkout
~/workspace/omarchy) and mirrors it — configs verbatim where
possible, scripts modeled on upstream flows — diverging only where
the U-Boot/no-installer constraints force it, with each divergence
recorded in this doc. All phases build and
verify the omarchy profile only; arch-gnome carries the shared Phase
0 boot layout for parity but is otherwise out of scope.
