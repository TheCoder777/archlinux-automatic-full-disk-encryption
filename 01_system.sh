#!/usr/bin/env bash
set -euo pipefail

# --- Core Configuration ---
TARGET_DISK="/dev/sda"
PART_EFI="${TARGET_DISK}1"
PART_BOOT="${TARGET_DISK}2"
PART_ROOT="${TARGET_DISK}3"

# --- System Preferences ---
HOST_NAME="example"
USERNAME="user"
# Note: passwords set here will be securely shredded after the install
SYS_PASS="root"
LUKS_PASS="luks"


TIMEZONE="Europe/Berlin"
KBD_LAYOUT="de"             # Console keymap
KBD_LOCALE="de-latin1"      # vconsole keymap
SYS_LOCALE="de_DE.UTF-8"    # System-wide language
USER_SHELL="bash"           # e.g. bash, zsh, fish, you can choose any shell available in the default archlinux repository
AUR_HELPER=""               # e.g. yay, paru, leave empty for none
CPU_UCODE="intel-ucode"     # e.g. amd-ucode or intel-ucode

echo ">>> Verifying UEFI Boot Mode"
if [ ! -f /sys/firmware/efi/fw_platform_size ]; then
    echo "ERROR: System did not boot in UEFI mode. Aborting."
    exit 1
fi

echo ">>> Setting installation keyboard layout"
loadkeys "${KBD_LAYOUT}"

echo ">>> Wiping disk and creating partitions"
sfdisk "${TARGET_DISK}" <<EOF
label: gpt
size=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
size=512M, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="BOOT"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="ROOT"
EOF

echo ">>> Formatting boot and EFI file systems"
mkfs.fat -F32 -n EFI "${PART_EFI}"
mkfs.ext4 -L BOOT "${PART_BOOT}"

echo ">>> Encrypting root partition"
echo -n "${LUKS_PASS}" | cryptsetup -v --batch-mode --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 5000 --use-random luksFormat "${PART_ROOT}" -

echo ">>> Opening encrypted drive"
echo -n "${LUKS_PASS}" | cryptsetup open "${PART_ROOT}" cryptroot -

echo ">>> Formatting encrypted drive"
mkfs.ext4 -L ROOT /dev/mapper/cryptroot

echo ">>> Mounting partitions"
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot/efi
mount "${PART_BOOT}" /mnt/boot
mount "${PART_EFI}" /mnt/boot/efi

echo ">>> Installing base system and shell"
pacstrap /mnt base base-devel linux linux-firmware "${CPU_UCODE}" vim nano git net-tools htop grub efibootmgr networkmanager sudo "${USER_SHELL}"

echo ">>> Generating fstab"
genfstab -Up /mnt >> /mnt/etc/fstab

echo ">>> Exporting variables for chroot env"
mkdir -p /mnt/root
cat <<EOF > /mnt/root/install_vars.sh
TARGET_DISK="${TARGET_DISK}"
PART_ROOT="${PART_ROOT}"
HOST_NAME="${HOST_NAME}"
USERNAME="${USERNAME}"
SYS_PASS="${SYS_PASS}"
TIMEZONE="${TIMEZONE}"
KBD_LOCALE="${KBD_LOCALE}"
SYS_LOCALE="${SYS_LOCALE}"
USER_SHELL="${USER_SHELL}"
AUR_HELPER="${AUR_HELPER}"
EOF
chmod 600 /mnt/root/install_vars.sh

echo ">>> Copying stage 2 script to new system"
cp ./02_chroot_system.sh /mnt/root/02_chroot_system.sh
chmod +x /mnt/root/02_chroot_system.sh

echo ">>> Changing into new system to execute Phase 2"
arch-chroot /mnt /bin/bash /root/02_chroot_system.sh

echo "The system was successfully installed, but it's currently secured with"
echo "the default, hardcoded installation passwords:"
echo "USERS: root, ${USERNAME}: ${SYS_PASSWORD}"
echo "Disc encryption: ${LUKS_PASS}"
echo ""
echo "It is highly reccomended that you change them:"
echo ""
echo "1. Update user password:"
echo "   sudo passwd $USERNAME"
echo ""
echo "2. Update root password:"
echo "   sudo passwd root"
echo ""
echo "3. Update your LUKS encryption password:"
echo "   sudo cryptsetup luksAddKey ${PART_ROOT}"
echo "   sudo cryptsetup luksRemoveKey ${PART_ROOT}"

echo ">>> Unmounting and closing encrypted drives"
umount -R /mnt
cryptsetup close cryptroot

echo ">>> System installation complete. Rebooting in 60 seconds"
echo ">>> Abort with Ctrl+C"
sleep 60

reboot