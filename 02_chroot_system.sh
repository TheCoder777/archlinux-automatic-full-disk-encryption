#!/usr/bin/env bash
set -euo pipefail

source /root/install_vars.sh

echo ">>> Setting timezone and sys to hw clock"
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

echo ">>> Configuring locales"
sed -i -e "s/#${SYS_LOCALE} UTF-8/${SYS_LOCALE} UTF-8/g" /etc/locale.gen
sed -i -e "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" /etc/locale.gen
locale-gen

echo "LANG=${SYS_LOCALE}" > /etc/locale.conf

echo ">>> Setting vconsole and hostname"
cat <<EOF > /etc/vconsole.conf
KEYMAP=${KBD_LOCALE}
FONT=lat9w-16
EOF

echo "${HOST_NAME}" > /etc/hostname

cat <<EOF > /etc/hosts
127.0.0.1    localhost
::1          localhost
127.0.1.1    ${HOST_NAME}.localdomain    ${HOST_NAME}
EOF

echo ">>> Configuring mkinitcpio for encryption"
sed -i '/^HOOKS=/c\HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)' /etc/mkinitcpio.conf
mkinitcpio -P

echo ">>> Installing and configuring GRUB (UEFI)"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch_grub --recheck

ENCRYPTED_UUID=$(blkid -o value -s UUID "${PART_ROOT}")
DECRYPTED_UUID=$(blkid -o value -s UUID /dev/mapper/cryptroot)
GRUB_CMDLINE="cryptdevice=UUID=${ENCRYPTED_UUID}:cryptroot root=UUID=${DECRYPTED_UUID}"

sed -i -e "s|GRUB_CMDLINE_LINUX=\"\"|GRUB_CMDLINE_LINUX=\"${GRUB_CMDLINE}\"|g" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

echo ">>> Enabling core services"
systemctl enable NetworkManager.service

echo ">>> Setting up users, passwords, and shell"
echo "root:${SYS_PASS}" | chpasswd

SHELL_PATH=$(which "${USER_SHELL}")
useradd -m -g users -G wheel -s "${SHELL_PATH}" "${USERNAME}"
echo "${USERNAME}:${SYS_PASS}" | chpasswd

echo ">>> Starting User-Space Provisioning (AUR)"
if [[ -n "${AUR_HELPER}" ]]; then
    echo ">>> Temporarily grant passwordless sudo for AUR helper install"
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
    chmod 440 /etc/sudoers.d/wheel

    # Switch to non-root user for cloning
    sudo -u "${USERNAME}" bash << EOF
        set -euo pipefail
        USER_HOME="/home/${USERNAME}"
        export TERM=xterm-256color # Prevents terminal errors during Vim plug install

        echo ">>> Installing ${AUR_HELPER} (AUR Helper)"
        mkdir -p "\${USER_HOME}/Downloads"
        cd "\${USER_HOME}/Downloads"
        git clone "https://aur.archlinux.org/${AUR_HELPER}.git"
        cd "${AUR_HELPER}"
        makepkg -si --noconfirm
EOF

    echo ">>> Reverting sudoers to standard secure configuration"
    echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
fi

echo ">>> Cleaning up sensitive files"
shred -u /root/install_vars.sh
shred -u /root/02_chroot_system.sh

echo ">>> Phase 2 complete, the system is ready"

exit