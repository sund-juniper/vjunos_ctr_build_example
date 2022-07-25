#!/usr/bin/env bash
set -eo pipefail

# VM DEFAULTS
VM_NAME=vjunos
VM_CPU_COUNT=4
VM_MEM=16384M
VM_NIC_COUNT=29
VM_CONSOLE_PORT=5000
VM_ARCH="x86_64"
VM_PID_FILE="$VM_NAME.pid"
VM_NIC_CMDS=()

# VRNETLAB STUFF
VRNETLAB=1 # FALSE
VM_MGMT_IFIDX=0

# MISC
IMG_DIR='/'
IMG_NAME='vJunos-ex-21.2R3-S1.7.qcow2'
PROG_NAME=$(basename $0)

trap cleanup EXIT

function log_msg() {
    local msg=$1
    echo "$(date --utc --iso-8601=seconds) - $msg"
}

# Kill socat relays and qemu process
function cleanup() {    
    log_msg "$PROG_NAME ending...cleaning up..." 
    # [[  -z $(jobs -p) ]] || kill -s SIGTERM $(jobs -p)
    cat $IMG_DIR/$VM_PID_FILE 2> /dev/null && kill -s SIGTERM $(cat $IMG_DIR/$VM_PID_FILE) && rm $IMG_DIR/$VM_PID_FILE
    log_msg "$PROG_NAME clean up complete..."
}

# TODO
# function bootstrap() {
# }

function usage() {
cat << EOF
USAGE: $PROG_NAME [OPTIONS...]

DESCRIPTION:
    $PROG_NAME starts up a containerized vjunos qemu instance.

OPTIONS:
    --cpus          VM_CPU_COUNT        Number of CPUs the VM will have
    --ram           VM_MEM              How much RAM the VM will have
    --nics          VM_NIC_COUNT        Number of NICs
    --console-port  VM_CONSOLE_PORT     TCP console port
    --name          VM_NAME             Name of the machine
    --vrnetlab      VRNETLAB            Generate vrnetlab style NICs
    --debug                             'set -x' for startup script

EXAMPLE:
    $PROG_NAME 
        --cpus $VM_CPU_COUNT \\
        --ram $VM_MEM \\
        --nics $VM_NIC_COUNT \\
        --console-port $VM_CONSOLE_PORT \\
        --name $VM_NAME \\ 
        --vrnetlab 

EOF
}

while [ $# -gt 0 ]; do

    case $1 in 
    -h|--help)
        usage; exit 1
        ;;
    --debug)
        set -x; shift;
        ;;
    --cpu)
        VM_CPU_COUNT=$2;shift;shift;
        ;;
    --mem)
        VM_MEM=$2;shift;shift;
        ;;   
    --nics)
        VM_NIC_COUNT=$2;shift;shift;
        ;;
    --console-port)
        VM_CONSOLE_PORT=$2;shift;shift;
        ;;
    --name)
        VM_NAME=$2;shift;shift;
        ;;
    --vrnetlab)
        VRNETLAB=0; shift;
        ;;
    --*)
        echo "\"$2\" is not a valid option" >&2
        usage; exit 1
        ;;
    *)
        echo "\"$1\" is not a valid option" >&2
        usage; exit 1

    esac
done

# main

BASE_MAC_SEED=$(xxd -ps -l 4 -g 4 /dev/urandom) # 32 bit mac base. 16 bits for port ifidx/id
VALID_SEED=1 # FALSE

until [ $VALID_SEED -eq 0 ]; do
    # 0100.5E00.0000 to 0100.5E7F.FFFF <- reserved mac ranges. Retry if base mac seed falls in this range.
    if (( 0x$BASE_MAC_SEED >= 0x01005e00 && 0x$BASE_MAC_SEED <= 0x01005e7f )); then
        BASE_MAC_SEED=$(xxd -ps -l 4 -g 4 /dev/urandom)
        continue
    else
        BASE_MAC=$( printf "$BASE_MAC_SEED" | sed -e 's/.\{2\}/&:/g' -e 's/.$//' )
        VALID_SEED=0
    fi
done

# Generate the qemu opts for nic
if [ ! VRNETLAB ]; then
    # TAP STYLE < - connected through CNI or other methods (manual ovs...linux bridges)
    for ((i = 0 ; i < $VM_NIC_COUNT ; i++)); do
        CLIENT_ID=$i
        MAC=$(printf "$BASE_MAC:%02x:%02x" $(($CLIENT_ID / 256 )) $(($CLIENT_ID % 256 )))
        VM_NIC_CMDS+=("-netdev tap,id=n$i,ifname=tap$i,script=no,downscript=no -device virtio-net-pci,netdev=n$i,mac=$MAC")
    done
else 
    # VRNETLAB STYLE
    for ((i = 0 ; i < $VM_NIC_COUNT ; i++)); do
        CLIENT_ID=$i
        MAC=$(printf "$BASE_MAC:%02x:%02x" $(($CLIENT_ID / 256 )) $(($CLIENT_ID % 256 )))
        IFIDX_SOCAT_PORT=$(expr 10000 + $i)

        # https://github.com/vrnetlab/vrnetlab/blob/master/common/vrnetlab.py#L19 
        # https://github.com/vrnetlab/vrnetlab/blob/master/common/vrnetlab.py#L157
        # https://github.com/vrnetlab/vrnetlab/blob/master/common/vrnetlab.py#L170
        if [ $VM_MGMT_IFIDX -eq $i ]; then

            MGMT_NIC=$(echo "-netdev user,id=n$i,net=10.0.0.0/24,tftp=/tftpboot,"\
            "hostfwd=tcp::2022-10.0.0.15:22,"\
            "hostfwd=udp::2161-10.0.0.15:161,"\
            "hostfwd=tcp::2830-10.0.0.15:830,"\
            "hostfwd=tcp::2080-10.0.0.15:80,"\
            "hostfwd=tcp::2443-10.0.0.15:443,"\
            "-device virtio-net-pci,netdev=n$i,mac=$MAC" | sed 's/\shostfwd/hostfwd/g')

           log_msg "Starting socat relays..."

            socat TCP-LISTEN:22,fork TCP:127.0.0.1:2022 &
            socat UDP-LISTEN:161,fork UDP:127.0.0.1:2161 &
            socat TCP-LISTEN:830,fork TCP:127.0.0.1:2830 &
            socat TCP-LISTEN:80,fork TCP:127.0.0.1:2080 &
            socat TCP-LISTEN:443,fork TCP:127.0.0.1:2443 &

            VM_NIC_CMDS+=($MGMT_NIC)
        else
            # https://github.com/vrnetlab/vrnetlab/blob/master/common/vrnetlab.py#L189
            # These are xconnected with the vr-xcon program.
            VM_NIC_CMDS+=("-netdev socket,id=n$i,listen=:$IFIDX_SOCAT_PORT -device virtio-net-pci,netdev=n$i,mac=$MAC")
        fi
    done
fi

log_msg "Starting VM $VM_NAME..."
/usr/bin/qemu-system-x86_64 \
  -name $VM_NAME -m $VM_MEM -smp $VM_CPU_COUNT,sockets=1,cores=$VM_CPU_COUNT,threads=1 -enable-kvm \
  -machine smm=off -boot order=c -display none -uuid $(uuidgen -r) \
  -no-user-config -nodefaults -pidfile $IMG_DIR/$VM_PID_FILE -daemonize \
  -serial telnet:0.0.0.0:$VM_CONSOLE_PORT,server,nowait \
  -chardev socket,id=charmonitor,host=0.0.0.0,port=8701,server,nowait \
  -mon chardev=charmonitor,id=monitor,mode=readline \
  -drive file=$IMG_DIR/$IMG_NAME,if=ide,index=0,media=disk,id=drive0 \
  ${VM_NIC_CMDS[*]} 

VM_PID=$!
log_msg "Running VM $VM_NAME on PID $!...Console port is $VM_CONSOLE_PORT"
wait $VM_PID

#   pty serial
#   -chardev pty,id=charserial0 \
#   -device isa-serial,chardev=charserial0,id=serial0 \

#   unix socket serial
#   -chardev socket,id=serial0,path=console.sock,server,nowait \
#   -serial chardev:serial0 \

# c1:c0:90:ea:00:00 - something about this mac juniper doesn't like...causes kernel panic
# virtio_pci0: host features: 0x511fffe3 <RingIndirect,NotifyOnEmpty,RxModeExtra,VLanFilter,RxMode,ControlVq,Status,MrgRxBuf,TxUFO,TxTSOECN,T>
# virtio_pci0: negotiated features: 0x100f8020 <RingIndirect,VLanFilter,RxMode,ControlVq,Status,MrgRxBuf,MacAddress>
