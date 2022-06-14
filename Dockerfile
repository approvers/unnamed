from archlinux/archlinux

run pacman -Sy --noconfirm archlinux-keyring && \
    pacman-key --init && \
    pacman-key --populate && \
    pacman -Su --noconfirm --needed base neovim sudo git && \
    rm -rf /var/cache/pacman
run useradd -m -G wheel john
run echo -e 'root ALL=(ALL) NOPASSWD: ALL\n%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers

user john
workdir /home/john/.config/nvim
run echo 'require("unnamed").setup({ "ishan9299/nvim-solarized-lua" })' > init.lua
