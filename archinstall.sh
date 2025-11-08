#!/usr/bin/env bash
set -euo pipefail

# ------------ 配置区（必要时修改） ------------
ROOT_PART="/dev/nvme0n1p7"
EFI_PART="/dev/nvme0n1p1"
HOSTNAME="archlinux"
USERNAME="BaiArch"
# 密码 = 五个空格（注意：脚本里以字面量五个空格设置）
PW="     "
# 镜像源（中国）
MIRRORS=(
  "Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/\$repo/os/\$arch"
  "Server = https://mirrors.bfsu.edu.cn/archlinux/\$repo/os/\$arch"
  "Server = https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch"
)
# ------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "请以 root 身份运行此脚本（在 live 环境）" >&2
  exit 1
fi

echo "==> 1) 设置本地 pacman 镜像列表（临时）"
cat > /etc/pacman.d/mirrorlist <<EOF
# China mirrors (set by script)
${MIRRORS[0]}
${MIRRORS[1]}
${MIRRORS[2]}
EOF

echo "==> 2) 格式化并挂载（注意：会格式化 ${ROOT_PART}）"
mkfs.ext4 -F "${ROOT_PART}"
mount "${ROOT_PART}" /mnt

# 挂载 EFI 到 /mnt/boot；不格式化 EFI 分区
mkdir -p /mnt/boot
mount "${EFI_PART}" /mnt/boot

echo "==> 3) 安装 base 系统与必要包（包含编译 AUR 所需）"
pacstrap /mnt \
  base linux linux-firmware base-devel networkmanager vim sudo git \
  intel-ucode nvidia nvidia-utils nvidia-settings \
  xorg sddm plasma kde-applications \
  grub efibootmgr \
  fcitx5-im fcitx5-chinese-addons fcitx5-configtool noto-fonts-cjk \
  wayland xdg-desktop-portal xdg-desktop-portal-wlr

echo "==> 4) 生成 fstab"
genfstab -U /mnt > /mnt/etc/fstab

echo "==> 5) 进入 chroot 执行配置"
arch-chroot /mnt /bin/bash <<'CHROOT'
set -euo pipefail

# variables inside chroot
HOSTNAME="archlinux"
USERNAME="BaiArch"
PW="     "   # 五个空格

echo "-> 设置时区与 locale（默认英文以避免 TTY 中文乱码）"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc
# 启用 en_US.UTF-8（保留 zh_CN.UTF-8 注释以便需要时启用）
sed -i 's/^#\s*\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen || true
sed -i 's/^#\s*\(zh_CN.UTF-8 UTF-8\)/\1/' /etc/locale.gen || true
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "-> 主机名与 /etc/hosts"
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

echo "-> 创建用户与设置密码（root 与 ${USERNAME} 的密码为5个空格）"
useradd -m -G wheel -s /bin/bash "${USERNAME}"

# 使用 printf 明确保留空格
printf "root:%s\n" "$PW" | chpasswd
printf "%s:%s\n" "${USERNAME}" "$PW" | chpasswd

# 允许 wheel 组使用 sudo
sed -i 's/^#\s*%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "-> 启用 NetworkManager 与 sddm"
systemctl enable NetworkManager
systemctl enable sddm

echo "-> 安装并配置 GRUB（EFI 模式）"
# 确保 /boot 已挂载（外部已挂载到 /boot）
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch || { echo "grub-install 失败"; exit 1; }
grub-mkconfig -o /boot/grub/grub.cfg

echo "-> 添加 archlinuxcn 源并安装 archlinuxcn-keyring"
cat >> /etc/pacman.conf <<'PACMANCFG'

[archlinuxcn]
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
PACMANCFG

# 同步并安装 keyring（避免交互）
pacman -Sy --noconfirm archlinuxcn-keyring

echo "-> 安装 yay（从 AUR 构建，使用 ${USERNAME} 用户）"
# 使用普通用户构建 yay
runuser -l "${USERNAME}" -c 'git clone https://aur.archlinux.org/yay.git /tmp/yay || true && cd /tmp/yay && makepkg -si --noconfirm' || { echo "yay 安装失败（尝试用 pacman 安装）..."; pacman -S --noconfirm yay || true; }

echo "-> 尝试安装 niri（先用 pacman，再用 yay）"
# 先用 pacman 安装（若存在）
if ! pacman -S --noconfirm niri >/dev/null 2>&1; then
  # 如 pacman 中不存在，使用 yay 安装（非交互）
  runuser -l "${USERNAME}" -c 'yay -S --noconfirm niri' || echo "niri 在仓库/AUR 中找不到或安装失败，跳过 niri。"
fi

echo "-> 配置输入法环境变量（放到用户目录）"
cat > /home/${USERNAME}/.pam_environment <<EOF
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.pam_environment

echo "-> 清理 pacman 缓存（可选）"
pacman -Scc --noconfirm || true

echo "配置完成（chroot 内）"
CHROOT

echo "==> 6) 卸载并完成"
umount -R /mnt || true

cat <<EOF

安装脚本执行完毕！

下一步建议：
  1) 输入 reboot 重启系统。
  2) 首次登录后请立即更改 root 与 ${USERNAME} 用户的密码（当前均为五个空格）。
  3) 如果你希望将系统语言改回中文，登录后编辑 /etc/locale.conf 为 zh_CN.UTF-8 并运行 locale-gen（或在安装时保留）。
  4) 若 niri 未成功安装，你可在系统内使用: 
       sudo pacman -Syu
       yay -S niri

EOF


