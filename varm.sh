#!/bin/bash -e

# Heavily based on terrific http://jerasure.org/bassamtabbara/gf-complete/blob/v2-simd-runtime-detection/tools/test_simd_qemu.sh
# created by Bassam Tabbara

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
qemu_dir="${script_dir}/.qemu"
ssh_port=2222
ssh_pubkey_file="${qemu_dir}/qemu.pub"
ssh_key_file="${qemu_dir}/qemu"
delta_disk="${qemu_dir}/disk.img"

image_version="xenial"

image_kernel="${image_version}-server-cloudimg-armhf-vmlinuz-lpae"
image_initrd="${image_version}-server-cloudimg-armhf-initrd-generic-lpae"
image_disk="${image_version}-server-cloudimg-armhf-disk1.img"

mkdir -p "${qemu_dir}"

cleanup() {
    if [[ -n "$(jobs -p)" ]]; then
        echo killing qemu processes "$(jobs -p)"
        kill $(jobs -p)
    fi
}

trap cleanup EXIT


init_image () {
    for i in "$@"
    do
    case ${i} in
        --resume=*)
        RESUME="${i#*=}"
        shift
        ;;
        *)
        ;;
    esac
    done

    image_url_base="http://cloud-images.ubuntu.com/${image_version}/current"

    if [[ ${RESUME} == "YES" ]]; then
        wget -c -O ${qemu_dir}/${image_kernel} ${image_url_base}/unpacked/${image_kernel}
        wget -c -O ${qemu_dir}/${image_initrd} ${image_url_base}/unpacked/${image_initrd}
        wget -c -O ${qemu_dir}/${image_disk} ${image_url_base}/${image_disk}
    else
        [[ -f ${qemu_dir}/${image_kernel} ]] || wget -O ${qemu_dir}/${image_kernel} ${image_url_base}/unpacked/${image_kernel}
        [[ -f ${qemu_dir}/${image_initrd} ]] || wget -O ${qemu_dir}/${image_initrd} ${image_url_base}/unpacked/${image_initrd}
        [[ -f ${qemu_dir}/${image_disk} ]] || wget -O ${qemu_dir}/${image_disk} ${image_url_base}/${image_disk}
    fi


    #create a delta disk to keep the original image clean
    rm -f ${delta_disk}
    qemu-img create -q -f qcow2 -b "${qemu_dir}/${image_disk}" ${delta_disk}

    # generate an ssh keys
    [[ -f ${ssh_pubkey_file} ]] || ssh-keygen -q -N "" -f ${ssh_key_file} 

    # create a config disk to set the SSH keys
    cat > "${qemu_dir}/meta-data" <<EOF 
instance-id: qemu
local-hostname: qemu
EOF
    cat > "${qemu_dir}/user-data" <<EOF 
#cloud-config
hostname: qemu
manage_etc_hosts: true
users:
  - name: qemu
    ssh-authorized-keys:
      - $(cat "${ssh_pubkey_file}")
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash
EOF
    genisoimage -quiet -output "${qemu_dir}/cloud.iso" -volid cidata -joliet -rock "${qemu_dir}/user-data" "${qemu_dir}/meta-data"
}

start_qemu() {
    arch=$1 ; shift
    cpu=$1 ; shift
    for i in "$@"
    do
    case ${i} in
        --serial=*)
        serial_dev="${i#*=}"
        shift
        ;;
        *)
        ;;
    esac
    done

    if [[ -z ${serial_dev} ]]; then
        serial_dev=file:${qemu_dir}/console.log
    fi

    common_args=( \
        -name "qemu" \
        -m 1024 \
        -nodefaults \
        -nographic \
        -kernel ${qemu_dir}/${image_kernel} \
        -initrd ${qemu_dir}/${image_initrd} \
        -cdrom ${qemu_dir}/cloud.iso \
        -serial ${serial_dev}
    )

    qemu-system-$arch \
        "${common_args[@]}" \
        -machine virt -cpu $cpu -machine type=virt -smp 1 \
        -drive if=none,file="${delta_disk}",id=hd0 \
        -device virtio-blk-device,drive=hd0 \
        -append "console=ttyAMA0 root=/dev/vda1" \
        -netdev user,id=eth0,hostfwd=tcp::"${ssh_port}"-:22,hostname="qemu" \
        -device virtio-net-device,netdev=eth0 \
        #
}

shared_args=(
    -i ${ssh_key_file}
    -F /dev/null
    -o BatchMode=yes
    -o UserKnownHostsFile=/dev/null
    -o StrictHostKeyChecking=no
    -o IdentitiesOnly=yes
)

ssh_args=(
    ${shared_args[*]}
    -p ${ssh_port}
)

run_ssh() {
    ssh -q ${ssh_args[*]} qemu@localhost "$@"
}

run_scp() {
    scp -q ${shared_args[*]} -P ${ssh_port} "$@"
}

run_main() {
    for i in "$@"
    do
    case ${i} in
        -i|--init)
        INIT_IMAGE=YES
        shift
        ;;
        -c|--continue)
        INIT_RESUME=YES
        shift
        ;;
        --stdio)
        SERIAL_DEV=stdio
        shift
        ;;
        --start)
        START=YES
        shift
        ;;
        --ssh)
        SSH=YES
        shift
        ;;
        --ssh=*)
        SSH=YES
        SSH_ARGS=${i#*=}
        shift
        ;;
        --scp=*)
        SCP=YES
        SCP_ARGS=${i#*=}
        shift
        ;;
        *)
        ;;
    esac
    done

    if [[ ${SSH} == "YES" ]]; then
        run_ssh ${SSH_ARGS}
        return
    fi

    if [[ ${SCP} == "YES" ]]; then
        run_scp ${SCP_ARGS}
        return
    fi

    if [[ ${INIT_IMAGE} == "YES" ]]; then
        init_image --resume=${INIT_RESUME}
    fi

    if [[ ${START} == "YES" ]]; then
        start_qemu "arm" "cortex-a15" --serial=${SERIAL_DEV}
    fi
}

run_main "$@"
exit $?
