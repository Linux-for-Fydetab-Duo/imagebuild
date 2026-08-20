# On-device installer plan (omarchy)

Status: DESIGN DRAFT 2026-08-20, awaiting review. No implementation
started. Decided so far: the on-device installer is the chosen route
to default-on disk encryption and factory reset (user decision
2026-08-20, superseding the first-boot in-place reencrypt flow parked
on the `luks-encryption` branch).

## Goal

Replace "flash the full image, then convert in place on first boot"
with "boot a small installer from SD, install to the target with
encryption on by default" — reaching most of the official Omarchy
install experience without touching boot firmware:

- LUKS2 on by default, created fresh at install time (encrypt-at-
  creation), with the official one-secret posture: the password
  collected at install is the account password, the LUKS passphrase,
  and (via upstream provisioning) the root password.
- `@factory` read-only baseline snapshot written at install end —
  the piece factory reset structurally lacks today
  (docs/omarchy-profile-plan.md ledger).
- eMMC installs without a PC: flash SD with Etcher, boot, tap
  install. rkdeveloptool/Loader mode becomes a recovery path, not
  the install path.

Explicitly out of scope: bootloader/firmware changes. U-Boot, the
ESP layout, boot.scr and PARTUUID root selection stay exactly as
shipped by the storage-stack rework (docs/storage-stack-plan.md).
The snapshot boot menu remains on the UEFI route.

## Why this beats the parked reencrypt flow

Measured on device (storage-stack Phase 3): in-place
`cryptsetup reencrypt` of the shipped root took 7m24s (image-size-
bound, ~11 GiB moved) plus one extra reboot, and forced a second
secret prompt after account creation. Creating the LUKS container
empty and copying the rootfs in is bounded by eMMC write speed on
~8 GiB of payload — minutes at worst — happens before any account
exists (so one secret, collected once), and needs no extra reboot.

## Facts the design builds on (all verified in this repo)

- Boot chain: vendor rockchip 2017.09 U-Boot boots whatever medium
  carries the EF00+legacy_boot ESP as partition 2; SD wins over eMMC
  when both are bootable. boot.cmd passes root=PARTUUID of partition
  3 on the same medium — an installer SD boots itself without
  touching the eMMC.
- Assembly is loop-free (stages/03-image.sh): the btrfs root is
  already produced as a standalone shrunk file (`mkfs.btrfs
  --rootdir --shrink`) before being dd'd into the image. That same
  file, compressed, IS the installer payload — no new build
  machinery.
- Provisioning: upstream omarchy-provision-owner runs a gum form on
  tty1, creates the owner, and sets root's password to the owner's
  (line 731). The installer must integrate with it, not replace it.
- The luks-encryption branch already carries a device-verified
  initramfs unlock hook (fydetab-crypt: prompt, keyfile handling,
  root= remap). The create-fresh flow reuses it; only the
  reencrypt/conversion parts retire.
- resizefs grows the root on first boot; an installer sizes the
  target partition at install time instead, so installed systems
  never need it (it stays for the direct-image path).

## Deliverables

Two release assets per release once this lands:

1. `...-Omarchy-installer-...img.xz` — the recommended download.
   Small SD image: FW blobs + ESP (kernel/initramfs/boot.scr as
   today) + installer rootfs + compressed payload.
2. `...-Omarchy-uboot-...img.xz` — today's direct image, kept for
   run-from-SD users and development. Unchanged behavior.

## Design

### Installer image layout

p1 FW (as today) | p2 ESP (as today) | p3 installer root (small
ext4 or btrfs, a trimmed Arch rootfs: systemd, gum, cryptsetup,
btrfs-progs, gptfdisk, zstd; no desktop) | p4 payload (the
compressed btrfs root file of the full image + its ESP file +
sha256s).

The installer boots exactly like every image we ship (same kernel,
same boot.scr pointing at p3), so stages 01-04 and 04-publish
assertions extend naturally: a new `omarchy-installer` profile
reusing the omarchy profile's boot/ and firmware/, with its own
packages.list and an overlay unit that runs the installer on tty1.

### Install flow (gum, tty1, mirrors the provisioning look)

1. Confirm target (default: the eMMC; refuse to target the boot
   medium in v1).
2. Encryption toggle, default ON.
3. Collect the owner account (same fields as upstream provisioning).
4. Partition target: FW + ESP + root sized to the full medium.
5. If encrypted: `cryptsetup luksFormat` p3 with the collected
   password, open it.
6. Write the payload btrfs into p3 (or the mapper device), regenerate
   the filesystem UUID, patch the target fstab, `btrfs filesystem
   resize max`. Write the ESP payload to p2 (its volume id already
   matches the payload fstab).
7. Chroot: stage the provisioning answers (open question 1), rebuild
   nothing — the payload already carries the right initramfs when
   unencrypted; for encrypted targets stage the fydetab-crypt hook's
   marker so the shipped initramfs prompts (the branch's initramfs
   already handles both cases).
8. Snapshot `@` → read-only `@factory`, identity-scrubbed (mirror
   omarchy-iso orchestrator/phases_impl.py).
9. Reboot to the target; first boot is upstream provisioning (or
   its preseeded fast path), NOT resizefs.

### Open questions (resolve in review before Phase A)

1. Provisioning preseed: can omarchy-provision-owner consume
   pre-collected answers, or does the installer create the owner
   itself in chroot and clear the pending marker? Probe upstream's
   script for a non-interactive path; owning it in the installer
   duplicates upstream logic we vowed to mirror, preseeding depends
   on upstream cooperation. This decides whether install collects
   the account (one form total) or only storage choices (two forms,
   but zero drift).
2. Release-asset size: payload.xz is ~1.9 GiB today and the 2 GiB
   GitHub cap is hard (learned on v0.1.5). Installer rootfs adds
   ~250-400 MiB compressed. Mitigations to measure in Phase A:
   shared kernel modules, aggressive installer trim, xz -9e
   (measured ~2-3% once), payload package diet. If it cannot fit,
   the installer image ships without the payload and fetches it over
   network at install time (changes the offline story — decide
   consciously).
3. btrfs UUID regeneration (`btrfstune -u`) rewrites metadata; speed
   on an ~8 GiB filesystem unmeasured. Alternative: keep the baked
   UUID and require removing the SD after install (duplicate-UUID
   hazard while both are inserted — reject unless measured
   unacceptable).
4. Install-to-same-SD (postmarketOS ondev supports it): deferred;
   the direct image covers run-from-SD.

## Phases

- Phase A — measurements + skeleton: answer open questions 1-3 with
  measurements; `omarchy-installer` profile boots on device to a gum
  hello-world on tty1. Gate: measured numbers reviewed, go/no-go on
  asset-size strategy.
- Phase B — unencrypted install path: full flow SD→eMMC minus LUKS.
  Gate: installed eMMC system boots, provisioning runs, @factory
  exists, fydetab-snapshot-restore drill passes.
- Phase C — encrypted-by-default path: luksFormat + one-secret +
  fydetab-crypt reuse. Gate: encrypted install boots with passphrase
  prompt (wrong-passphrase retry verified), performance recorded.
- Phase D — factory reset end-to-end: wire
  omarchy-system-factory-reset against @factory; audit its
  Limine/LUKS-rekey assumptions (ledger entry). Gate: reset drill on
  device returns it to first-boot state.
- Phase E — polish + release: unl0kr (touch on-screen keyboard at
  the LUKS prompt — postmarketOS/Mobian's solution; vendored
  package + initramfs integration), progress/error UI, CI builds
  both assets, wiki + release-notes rewrite of the install story.

Each phase lands only after on-device verification, one commit per
verified change, per the working rules that governed the
storage-stack rounds.

## Cross-references

- docs/storage-stack-plan.md — layout this builds on; Phase 3 holds
  the LUKS deferral rationale and measurements this design answers.
- docs/omarchy-profile-plan.md deferred ledger — @factory entry,
  LUKS re-entry entry (both superseded by this plan when it lands),
  UEFI route (unchanged, still owns the boot menu).
- Branch `luks-encryption` — source of the fydetab-crypt hook and
  the encrypt-setup gum patterns to be reused.
