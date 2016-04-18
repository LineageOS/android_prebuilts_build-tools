#!/bin/bash -ex

if [ -z "${OUT_DIR}" ]; then
    echo Must set OUT_DIR
    exit 1
fi

TOP=$(pwd)

UNAME="$(uname)"
case "$UNAME" in
Linux)
    OS='linux'
    ;;
Darwin)
    OS='darwin'
    ;;
*)
    exit 1
    ;;
esac

build_soong=1
if [ -d ${TOP}/toolchain/go ]; then
    build_go=1
fi
if [ -d ${TOP}/external/ninja ]; then
    build_ninja=1
fi

if [ -n ${build_soong} ]; then
    # ckati and makeparallel (Soong)
    SOONG_OUT=${OUT_DIR}/soong
    SOONG_HOST_OUT=${OUT_DIR}/soong/host/${OS}-x86
    rm -rf ${SOONG_OUT}
    mkdir -p ${SOONG_OUT}
    cat > ${SOONG_OUT}/soong.variables << EOF
{
    "Allow_missing_dependencies": true,
    "HostArch":"x86_64",
    "HostSecondaryArch":"x86",

    "DeviceName": "generic",
    "DeviceArch": "arm",
    "DeviceArchVariant": "armv7-a",
    "DeviceCpuVariant": "generic"
}
EOF
    BUILDDIR=${SOONG_OUT} ./bootstrap.bash
    ${SOONG_OUT}/soong ${SOONG_HOST_OUT}/bin/ckati ${SOONG_HOST_OUT}/bin/makeparallel
    (
        cd ${SOONG_HOST_OUT}
        zip -qryX build-prebuilts.zip bin/ lib*/
    )
fi

# Ninja
if [ -n ${build_ninja} ]; then
    NINJA_OUT=${OUT_DIR}/obj/ninja
    rm -rf ${NINJA_OUT}
    mkdir -p ${NINJA_OUT}
    (
        cd ${NINJA_OUT}
        ${TOP}/external/ninja/configure.py --bootstrap
    )
fi

# Go
if [ -n ${build_go} ]; then
    GO_OUT=${OUT_DIR}/obj/go
    rm -rf ${GO_OUT}
    mkdir -p ${GO_OUT}
    cp -a ${TOP}/toolchain/go/* ${GO_OUT}/
    (
        cd ${GO_OUT}/src
        export GOROOT_BOOTSTRAP=${TOP}/prebuilts/go/${OS}-x86
        export GOROOT_FINAL=./prebuilts/go/${OS}-x86
        export GO_TEST_TIMEOUT_SCALE=100
        ./make.bash
        GOROOT=$(pwd)/.. ../bin/go install -race std
    )
    (
        cd ${GO_OUT}
        zip -qryX go.zip *
    )
fi

if [ -n "${DIST_DIR}" ]; then
    mkdir -p ${DIST_DIR} || true

    if [ -n ${build_soong} ]; then
        cp ${SOONG_HOST_OUT}/build-prebuilts.zip ${DIST_DIR}/
    fi
    if [ -n ${build_ninja} ]; then
        cp ${NINJA_OUT}/ninja ${DIST_DIR}/
    fi
    if [ -n ${build_go} ]; then
        cp ${GO_OUT}/go.zip ${DIST_DIR}/
    fi
fi
