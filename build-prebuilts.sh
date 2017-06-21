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
    "HostSecondaryArch":"x86"
}
EOF
    BUILDDIR=${SOONG_OUT} ./bootstrap.bash
    SOONG_BINARIES=(
        acp
        bpfmt
        ckati
        ckati_stamp_dump
        header-abi-linker
        header-abi-dumper
        header-abi-diff
        ijar
        makeparallel
        merge-abi-diff
        ninja
        soong_zip
        zip2zip
        ziptime
    )
    SOONG_ASAN_BINARIES=( acp ckati ijar makeparallel ninja ziptime )
    ${SOONG_OUT}/soong ${SOONG_BINARIES[@]/#/${SOONG_HOST_OUT}/bin/} ${SOONG_HOST_OUT}/nativetest64/ninja_test/ninja_test
    ${SOONG_HOST_OUT}/nativetest64/ninja_test/ninja_test
    mkdir -p ${SOONG_OUT}/dist/bin
    cp ${SOONG_BINARIES[@]/#/${SOONG_HOST_OUT}/bin/} ${SOONG_OUT}/dist/bin/
    cp -R ${SOONG_HOST_OUT}/lib* ${SOONG_OUT}/dist/

    if [[ $OS == "linux" ]]; then
        # Build ASAN versions
        export ASAN_OPTIONS=detect_leaks=0
        cat > ${SOONG_OUT}/soong.variables << EOF
{
    "Allow_missing_dependencies": true,
    "HostArch":"x86_64",
    "HostSecondaryArch":"x86",
    "SanitizeHost": ["address"]
}
EOF
        rm -rf ${SOONG_HOST_OUT}
        ${SOONG_OUT}/soong ${SOONG_ASAN_BINARIES[@]/#/${SOONG_HOST_OUT}/bin/} ${SOONG_HOST_OUT}/nativetest64/ninja_test/ninja_test
        ${SOONG_HOST_OUT}/nativetest64/ninja_test/ninja_test
        mkdir -p ${SOONG_OUT}/dist/asan/bin
        cp ${SOONG_ASAN_BINARIES[@]/#/${SOONG_HOST_OUT}/bin/} ${SOONG_OUT}/dist/asan/bin/
        cp -R ${SOONG_HOST_OUT}/lib* ${SOONG_OUT}/dist/asan/
    fi

    (
        cd ${SOONG_OUT}/dist
        zip -qryX build-prebuilts.zip *
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
        rm -rf ../pkg/bootstrap
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
        cp ${SOONG_OUT}/dist/build-prebuilts.zip ${DIST_DIR}/
        cp ${SOONG_OUT}/.bootstrap/docs/soong_build.html ${DIST_DIR}/
    fi
    if [ -n ${build_go} ]; then
        cp ${GO_OUT}/go.zip ${DIST_DIR}/
    fi
fi
