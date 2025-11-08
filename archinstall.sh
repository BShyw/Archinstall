#!/usr/bin/env bash
set -e

echo "===> [1/10] Set China mirrors"
cat > /etc/pacman.d/mirrorlist <<'EOF'
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.bfsu.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
EOF

echo "===> [2/10] Format and mount partitions"
mkfs.ext4 -F /dev/nvme0n1p7
mount /dev/nvme0n1p7 /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot

echo "===> [3/10] Install base system and essential packages"
pacstrap /mnt base linux linux-firmware networkmanager vim sudo grub efibootmgr \
    intel-ucode nvidia nvidia-utils nvidia-settings \
    xorg plasma kde-applications sddm \
    niri wayland xdg-desktop-portal xdg-desktop-portal-wlr \
    fcitx5-im fcitx5-chinese-addons fcitx5-configtool noto-fonts-cjk git base-devel

echo "===> [4/10] Generate fstab"
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<'CHROOT_CMDS'
set -e

echo "===> [5/10] Set timezone and locale (English default)"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc
sed -i 's/^#\(en_US.UTF-8\|zh_CN.UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "===> [6/10] Set hostname and hosts"
echo "archlinux" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   archlinux.localdomain archlinux
EOF

echo "===> [7/10] Create user BaiArch (password = 5 spaces)"
useradd -m -G wheel -s /bin/bash BaiArch
echo "root:     " | chpasswd
echo "BaiArch:     " | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "===> [8/10] Enable services"
systemctl enable NetworkManager
systemctl enable sddm

echo "===> [9/10] Install and configure GRUB"
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg

echo "===> [10/10] Add archlinuxcn repo and install yay"
cat >> /etc/pacman.conf <<EOF

[archlinuxcn]
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
EOF
pacman -Sy --noconfirm archlinuxcn-keyring
pacman -S --noconfirm yay

echo "===> Configure input method environment"
cat > /home/BaiArch/.pam_environment <<EOF
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF
chown BaiArch:BaiArch /home/BaiArch/.pam_environment

echo "===> Installation completed successfully! You may exit and reboot."
CHROOT_CMDS

umount -R /mnt
echo "Installation done. Type 'reboot' to restart."
