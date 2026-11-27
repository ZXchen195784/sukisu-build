#!/bin/sh
set -eu

# SukiSU Nova (SukiSU Ultra) integration script for non-GKI kernels
# Adapted from SukiSU official kernel/setup.sh to use GitHub mirror
# Usage: run from kernel source root, optional arg = tag/commit

GKI_ROOT=$(pwd)
OWNER="SukiSU-Nova"
REPO="SukiSU-Nova"
# GitHub mirror instead of self-hosted git.zako.shirkneko.top (unreachable in CI)
CLONE_URL="https://github.com/${OWNER}/${REPO}.git"

display_usage() {
    echo "Usage: $0 [--cleanup | <commit-or-tag>]"
    echo "  --cleanup:        Remove previous modifications."
    echo "  <commit-or-tag>:  Checkout specific tag or commit."
    echo "  (no args):        Checkout latest tag."
}

initialize_variables() {
    if test -d "$GKI_ROOT/common/drivers"; then
         DRIVER_DIR="$GKI_ROOT/common/drivers"
    elif test -d "$GKI_ROOT/drivers"; then
         DRIVER_DIR="$GKI_ROOT/drivers"
    else
         echo '[ERROR] "drivers/" directory not found.'
         exit 127
    fi
    DRIVER_MAKEFILE=$DRIVER_DIR/Makefile
    DRIVER_KCONFIG=$DRIVER_DIR/Kconfig
}

perform_cleanup() {
    echo "[+] Cleaning up..."
    [ -L "$DRIVER_DIR/kernelsu" ] && rm "$DRIVER_DIR/kernelsu" && echo "[-] Symlink removed."
    grep -q "kernelsu" "$DRIVER_MAKEFILE" && sed -i '/kernelsu/d' "$DRIVER_MAKEFILE" && echo "[-] Makefile reverted."
    grep -q "drivers/kernelsu/Kconfig" "$DRIVER_KCONFIG" && sed -i '/drivers\/kernelsu\/Kconfig/d' "$DRIVER_KCONFIG" && echo "[-] Kconfig reverted."
    if [ -d "$GKI_ROOT/SukiSU" ]; then
        rm -rf "$GKI_ROOT/SukiSU" && echo "[-] SukiSU directory deleted."
    fi
}

setup_sukisu() {
    echo "[+] Setting up SukiSU Nova from $CLONE_URL ..."
    test -d "$GKI_ROOT/SukiSU" || git clone --depth=1 "$CLONE_URL" "$GKI_ROOT/SukiSU" && echo "[+] Repository cloned."
    cd "$GKI_ROOT/SukiSU"

    # Compatibility patch for old (4.19 / non-GKI) kernels:
    # MODULE_IMPORT_NS was introduced in Linux 5.2. Kernel 4.19 has no such macro,
    # so the call in core/init.c fails with -Werror,-Wimplicit-int. Namespace import
    # does not exist on 4.19 anyway, so commenting those lines out is safe.
    echo "[+] Patching MODULE_IMPORT_NS for 4.19 kernel compatibility..."
    find "$GKI_ROOT/SukiSU/kernel" -name '*.c' -type f | while read -r f; do
        if grep -q "MODULE_IMPORT_NS" "$f"; then
            sed -i 's/^\([[:space:]]*\)MODULE_IMPORT_NS/\1\/\/MODULE_IMPORT_NS/' "$f"
            echo "    patched: $(basename "$f")"
        fi
    done

    if [ -z "${1-}" ]; then
        # Shallow clone does not fetch tags; just use the default branch HEAD.
        echo "[-] Using default branch HEAD (latest kernel code)."
    else
        git fetch --depth=1 origin "$1" 2>/dev/null || true
        git checkout "$1" 2>/dev/null && echo "[-] Checked out $1." || echo "[-] Checkout failed, using default branch."
    fi

    cd "$DRIVER_DIR"
    ln -sf "$(realpath --relative-to="$DRIVER_DIR" "$GKI_ROOT/SukiSU/kernel")" "kernelsu" && echo "[+] Symlink created."

    grep -q "kernelsu" "$DRIVER_MAKEFILE" || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> "$DRIVER_MAKEFILE" && echo "[+] Modified Makefile."
    grep -q "source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG" || sed -i "/endmenu/i\source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG" && echo "[+] Modified Kconfig."
    echo '[+] SukiSU integration done.'
}

if [ "$#" -eq 0 ]; then
    initialize_variables
    setup_sukisu
elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    display_usage
elif [ "$1" = "--cleanup" ]; then
    initialize_variables
    perform_cleanup
else
    initialize_variables
    setup_sukisu "$@"
fi
