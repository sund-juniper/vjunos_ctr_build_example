# vjunos_ctr_build_example

## Get vrnetlab and build vx-con
1. `git https://github.com/vrnetlab/vrnetlab.git`
2. `cd vrnetlab/vr-xcon`
3. `make && sudo docker tag vrnetlab/vr-xcon:latest vr-xcon`


## Build images

Place vjunos image with the docker file and run `docker build -t vjunos:test .`
```
root@dysun-desktop:/tmp/vrnetlab/vjunos# ls
Dockerfile  start_vm.sh  vJunos-ex-21.2R3-S1.7.qcow2
```


## Spin up containers and connect
```
docker run -d  --privileged --name vjunos1 vjunos:test --vrnetlab
docker run -d  --privileged --name vjunos2 vjunos:test --vrnetlab
docker run -d --name vr-xcon-vjunos --link vjunos1 --link vjunos2 vr-xcon --p2p vjunos1/2--vjunos2/2
```

## Inspect container details
```
root@dysun-desktop:/tmp/vrnetlab/vr-xcon# docker ps -a
CONTAINER ID   IMAGE                      COMMAND                  CREATED          STATUS                 PORTS                                                                  NAMES
ee6abf30cf01   vr-xcon                    "/xcon.py --p2p vjun…"   6 seconds ago    Up 4 seconds                                                                                  vr-xcon-vjunos
45e337023515   vjunos:test                "/start_vm.sh --vrne…"   59 minutes ago   Up 55 minutes          22/tcp, 80/tcp, 443/tcp, 830/tcp, 5000/tcp, 10000-10099/tcp, 161/udp   vjunos2
78a2fda69072   vjunos:test                "/start_vm.sh --vrne…"   59 minutes ago   Up 59 minutes          22/tcp, 80/tcp, 443/tcp, 830/tcp, 5000/tcp, 10000-10099/tcp, 161/udp   vjunos1

root@dysun-desktop:/home/dysun# docker inspect -f '{{.NetworkSettings.IPAddress}}' vjunos1
172.17.0.5
root@dysun-desktop:/home/dysun# docker inspect -f '{{.NetworkSettings.IPAddress}}' vjunos2
172.17.0.6
root@dysun-desktop:/home/dysun#
```

## Bootstrap commands/procedure
No bootstrap script yet...

root password = 'root123'

```
root@dysun-desktop:/home/dysun# telnet 172.17.0.6 5000
Trying 172.17.0.6...
Connected to 172.17.0.6.
Escape character is '^]'.

[edit]
root@vjunos2# load set terminal 
[Type ^D at a new line to end input]
set system host-name vjunos2
set system services ssh root-login allow
set system services netconf ssh port 830
delete chassis auto-image-upgrade
delete interfaces fxp0 unit 0
set interfaces fxp0 unit 0 family inet address 10.0.0.15/24
set system root-authentication encrypted-password "$6$NhYfhjMr$w5z.zvc91lsmv6pMgLzqs8jSruF/PLS53gIK8H2u.pSVPVN0dYIfFbhMBa5fqo/swHle4T0Elro45gc1aHxJk/"
delete chassis
load complete

[edit]
root@vjunos2# commit 
commit complete

[edit]
root@vjunos2# 
```

## Verify connectivity

Shows dataplane connectivity wired up through `vr-xcon` tool. 
```
root@vjunos2# run show lldp neighbors 
Local Interface    Parent Interface    Chassis Id          Port info          System Name
ge-0/0/1           -                   2c:6b:f5:e6:92:c0   ge-0/0/1           vjunos1 

root@dysun-desktop:/home/dysun# ssh 172.17.0.6 
Password:
Last login: Mon Jul 25 09:47:22 2022 from 10.0.0.2
--- JUNOS 21.2R3-S1.7 Kernel 64-bit  JNPR-12.1-20220405.04197b6_buil
root@vjunos2:~ # 

```
