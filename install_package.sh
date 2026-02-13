#!/bin/sh

sudo apt update && sudo apt install -y \
    git build-essential flex bison bc rsync unzip \
    libssl-dev libelf-dev libncurses-dev \
    gcc-aarch64-linux-gnu gdb-multiarch \
    qemu-system-x86 qemu-system-arm \
    cpio pahole
