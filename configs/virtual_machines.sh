#!/bin/bash
# shellcheck disable=SC2034
set -a

# The primary use of this virtual machine installer is for a Windows 10/11 gaming VM.
domain_name="win10"

if core_isolation="1"; then
    # C0-C15: For Intel i7-12700k P-cores.
    VM_CORES="C0-C15"
    # Cores you want the (Arch Linux/Dux) host to keep.
    HOST_CORES="C16-C19"
fi

dynamic_hugepages="1"
