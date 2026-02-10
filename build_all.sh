#!/bin/bash

# 소스가 없으면 가져오는 로직 추가
if [ ! -d "./linux" ]; then
    git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
fi

if [ ! -d "./busybox" ]; then
    wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2
    tar -xjf busybox-1.36.1.tar.bz2 && mv busybox-1.36.1 busybox
fi

# 설정을 위한 변수 (사용자 환경에 맞게 수정 가능)
KERNEL_SRC="./linux"
BUSYBOX_INSTALL="./busybox_build/_install" # 각 아키텍처 build 폴더 내 기준
THREADS=$(nproc)

# 빌드 함수 정의
build_kernel() {
    ARCH=$1
    CROSS=$2
    OUT_DIR="../build-$ARCH"
    
    echo "========================================"
    echo "[+] Starting Build for $ARCH"
    echo "========================================"


    # 2. 커널 빌드
    cd "$KERNEL_SRC"
    # 최초 빌드 시에만 defconfig 적용 (원할 경우 실행 시 인자로 구분 가능)
    if [ ! -f "$OUT_DIR/.config" ]; then
        make O="$OUT_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS" defconfig
        echo "[*] Default config applied for $ARCH. Please check DEBUG options manually if needed."
    fi
    
    make O="$OUT_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS" -j"$THREADS"
    #cd ..

    # 1. 출력 디렉토리 생성
    mkdir -p "$OUT_DIR/rootfs"

    # 3. Rootfs 구성 (BusyBox 및 init)
    echo "[+] Updating Rootfs for $ARCH..."
    cp -av "$OUT_DIR/$BUSYBOX_INSTALL/"* "$OUT_DIR/rootfs/" 2>/dev/null
    mkdir -p "$OUT_DIR/rootfs/"{proc,sys,dev,etc,tmp}

    # init 스크립트가 없으면 생성
    if [ ! -f "$OUT_DIR/rootfs/init" ]; then
        cat <<EOF > "$OUT_DIR/rootfs/init"
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
echo 0 > /proc/sys/kernel/kptr_restrict
echo "--- Kernel Lab ($ARCH) Ready ---"
setsid /bin/cttyhack setuidgid 0 /bin/sh
poweroff -d 0 -f
EOF
        chmod +x "$OUT_DIR/rootfs/init"
    fi

    # 4. Ramdisk(cpio) 생성
    echo "[+] Packing Rootfs image..."
    cd "$OUT_DIR/rootfs"
    find . | cpio -o --format=newc > ../rootfs.img
    cd ../..
    
    echo "[!] $ARCH build and packaging complete."
}

# 실행 옵션 처리
case "$1" in
    x86)
        build_kernel "x86_64" ""
        ;;
    arm)
        build_kernel "aarch64" "aarch64-linux-gnu-"
        ;;
    all)
        build_kernel "x86_64" ""
        build_kernel "aarch64" "aarch64-linux-gnu-"
        ;;
    *)
        echo "Usage: $0 {x86|aarch64|all}"
        exit 1
        ;;
esac
