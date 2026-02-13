#!/bin/bash

# =================================================================
# 1. 소스 다운로드 및 준비
# =================================================================
if [ ! -d "./linux" ]; then
    echo "[*] Cloning Linux Kernel..."
    git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
fi

if [ ! -d "./busybox" ]; then
    echo "[*] Downloading BusyBox..."
    wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2
    tar -xjf busybox-1.36.1.tar.bz2
    mv busybox-1.36.1 busybox
    rm busybox-1.36.1.tar.bz2
fi

# =================================================================
# 2. 환경 변수 설정
# =================================================================
KERNEL_SRC="./linux"
BUSYBOX_SRC="./busybox"
THREADS=$(nproc)

# =================================================================
# 3. 빌드 함수 정의
# =================================================================
build_kernel() {
    ARCH=$1
    CROSS=$2
    
    # 아키텍처별 빌드 디렉토리 분리
    OUT_DIR="../build-$ARCH"
    KERNEL_OUT="$OUT_DIR/kernel"
    BUSYBOX_OUT="$OUT_DIR/busybox"
    ROOTFS_DIR="$OUT_DIR/rootfs"
    
    echo "========================================"
    echo "[+] Starting Process for $ARCH"
    echo "========================================"

    # 폴더 생성
    mkdir -p "$KERNEL_OUT"
    mkdir -p "$BUSYBOX_OUT"
    mkdir -p "$ROOTFS_DIR"

    # ---------------------------------------------------------
    # [Step 1] BusyBox 빌드 (Arch별 설정 적용)
    # ---------------------------------------------------------
    echo "[*] Configuring & Building BusyBox ($ARCH)..."
    
    # 1. Defconfig 생성 (소스 폴더 밖에서 빌드: O=옵션)
    if [ ! -f "$BUSYBOX_OUT/.config" ]; then
        make -C "$BUSYBOX_SRC" O="$BUSYBOX_OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS" defconfig > /dev/null
        
        # 2. 필수 설정 패치 (.config 수정)
        # 중요: Static Linking 활성화 (공유 라이브러리 없이 실행되도록)
        sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' "$BUSYBOX_OUT/.config"
        
        # 중요: 빌드 에러를 유발하는 TC(Traffic Control) 기능 비활성화
        sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/' "$BUSYBOX_OUT/.config"
        sed -i 's/^CONFIG_FEATURE_TC_INGRESS=y/# CONFIG_FEATURE_TC_INGRESS is not set/' "$BUSYBOX_OUT/.config"
    fi

    # 3. 빌드 및 설치 (_install 폴더 생성)
    make -C "$BUSYBOX_SRC" O="$BUSYBOX_OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS" -j"$THREADS" install > /dev/null
    
    echo "[+] BusyBox build complete."

    # ---------------------------------------------------------
    # [Step 2] 리눅스 커널 빌드
    # ---------------------------------------------------------
    echo "[*] Building Kernel ($ARCH)..."
    
    # 최초 빌드 시에만 defconfig 적용
    if [ ! -f "$KERNEL_OUT/.config" ]; then
        make -C "$KERNEL_SRC" O="$KERNEL_OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS" defconfig > /dev/null
        # KVM용 최적화 설정 추가 (선택 사항)
        make -C "$KERNEL_SRC" O="$KERNEL_OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS" kvm_guest.config > /dev/null
        
        # 디버그 정보 활성화 (GDB용) - 선택 사항
        # echo "CONFIG_DEBUG_INFO=y" >> "$KERNEL_OUT/.config"
        # echo "CONFIG_GDB_SCRIPTS=y" >> "$KERNEL_OUT/.config"
    fi
    
    make -C "$KERNEL_SRC" O="$KERNEL_OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS" -j"$THREADS"
    
    # ---------------------------------------------------------
    # [Step 3] Rootfs 구성 (BusyBox _install 복사)
    # ---------------------------------------------------------
    echo "[+] Updating Rootfs for $ARCH..."
    
    # BusyBox 설치 결과물을 rootfs로 복사
    cp -av "$BUSYBOX_OUT/_install/"* "$ROOTFS_DIR/" > /dev/null
    
    # 필수 디렉토리 생성
    mkdir -p "$ROOTFS_DIR/"{proc,sys,dev,etc,tmp,home/root}

    # init 스크립트 생성 (없을 경우)
    if [ ! -f "$ROOTFS_DIR/init" ]; then
        cat <<EOF > "$ROOTFS_DIR/init"
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts
echo 0 > /proc/sys/kernel/kptr_restrict
echo "--- Kernel Lab ($ARCH) Ready ---"
# 루트 권한 쉘 실행
setsid cttyhack /bin/sh
poweroff -f
EOF
        chmod +x "$ROOTFS_DIR/init"
    fi

    # ---------------------------------------------------------
    # [Step 4] Ramdisk(cpio) 패키징
    # ---------------------------------------------------------
    echo "[+] Packing Rootfs image..."
    cd "$ROOTFS_DIR"
    find . -print0 | cpio --null -o --format=newc > "$OUT_DIR/rootfs.cpio"
    cd - > /dev/null
    
    echo "========================================"
    echo "[!] Build Success for $ARCH"
    echo "    Kernel: $KERNEL_OUT/arch/$ARCH/boot/"
    echo "    Rootfs: $OUT_DIR/rootfs.cpio"
    echo "========================================"
}

# =================================================================
# 4. 실행 옵션 처리
# =================================================================
case "$1" in
    x86)
        build_kernel "x86_64" ""
        ;;
    arm)
        build_kernel "arm64" "aarch64-linux-gnu-"
        ;;
    all)
        build_kernel "x86_64" ""
        build_kernel "arm64" "aarch64-linux-gnu-"
        ;;
    *)
        echo "Usage: $0 {x86|arm|all}"
        exit 1
        ;;
esac
