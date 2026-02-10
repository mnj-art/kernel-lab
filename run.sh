#!/bin/bash

# 사용법 안내 함수
usage() {
    echo "Usage: $0 {x86|aarch64} [{gdb|nogdb}]"
    echo "Example: $0 x86 gdb"
    echo "Example: $0 x86"
    exit 1
}

# 인자 개수 확인
if [ "$#" -lt 1 ]; then
    usage
fi

ARCH_TYPE=$1
GDB_OPTION=$2

# GDB 대기 옵션 설정 (-s: 1234 포트 오픈, -S: CPU 시작 전 정지)
GDB_FLAGS=""
if [ "$GDB_OPTION" == "gdb" ]; then
    GDB_FLAGS="-s -S"
    echo "[*] QEMU will wait for GDB connection on port 1234..."
fi

# 아키텍처별 실행
case "$ARCH_TYPE" in
    x86)
        echo "[+] Launching x86_64 QEMU..."
        qemu-system-x86_64 \
	    -m 512M -nographic \
            $GDB_FLAGS \
            -kernel ./build-x86_64/arch/x86/boot/bzImage \
            -initrd ./build-x86_64/rootfs.img \
            -cpu kvm64,+smep,+smap \
	    -append "console=ttyS0 root=/dev/ram rdinit=/init nokaslr"
        ;;
    aarch64)
        echo "[+] Launching aarch64 (ARM64) QEMU..."
        # ARM64는 기기(virt) 및 CPU(cortex-a57) 명시 필요
        # console 옵션이 ttyAMA0로 변경됨에 유의
        qemu-system-aarch64 \
            -M virt -cpu cortex-a57 \
            -m 512M -nographic \
            $GDB_FLAGS \
            -kernel ./build-aarch64/arch/arm64/boot/Image \
            -initrd ./build-aarch64/rootfs.img \
            -append "console=ttyAMA0 root=/dev/ram rdinit=/init nokaslr"
        ;;
    *)
        usage
        ;;
esac


