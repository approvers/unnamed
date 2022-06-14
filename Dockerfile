from archlinux/archlinux

run pacman -Syu --noconfirm --needed base neovim sudo && \
    rm -rf /var/cache/pacman
run useradd -m -G wheel john
run echo 'root ALL=(ALL) ALL\n%wheel ALL=(ALL) ALL' > /etc/sudoers

user john
workdir /home/john/.config/nvim
run echo 'require("unnamed").setup({ "ishan9299/nvim-solarized-lua" })' > init.lua
