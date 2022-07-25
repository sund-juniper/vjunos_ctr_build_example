FROM debian:11
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y && apt-get upgrade -y  && \
    apt-get install -y  \
        qemu-kvm \
        xxd \ 
        uuid-runtime  \
        socat && \
    rm -rf /var/lib/apt/lists/*

COPY "." "/"
EXPOSE 22 161/udp 80 443 830 5000 10000-10099
ENTRYPOINT ["/start_vm.sh"]
