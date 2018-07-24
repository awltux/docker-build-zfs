FROM %DOCKER_FROM_IMAGE_NAME%

# Change this to trigger and effectively date/tag a full re-build
LABEL build="20180718001"

# Create an updated image; improves build times
RUN yum -y update

RUN yum install -y \
     autoconf automake binutils bison flex gcc gcc-c++ gdb glibc-devel \
     libtool make pkgconfig strace byacc ccache cscope ctags \
     indent ltrace oprofile valgrind ElectricFence astyle cbmc check \
     cmake coan cproto insight nasm pscan remake scons scorep \
     splint trinity elfutils yasm zzuf \
     koji git \
     zlib-devel libuuid-devel libattr-devel \
     libblkid-devel libselinux-devel libudev-devel \
     parted lsscsi ksh openssl-devel elfutils-libelf-devel \
     file libtirpc-devel rpm-build

# Koji is only relevant for Fedora
RUN koji download-build --rpm --arch=%PROCESSOR_ARCH% \
          kernel-core-%KERNEL_RELEASE%

RUN koji download-build --rpm --arch=%PROCESSOR_ARCH% \
          kernel-devel-%KERNEL_RELEASE%

RUN koji download-build --rpm --arch=%PROCESSOR_ARCH% \
          kernel-modules-%KERNEL_RELEASE%

RUN yum localinstall -y \
     kernel-core-%KERNEL_RELEASE%.rpm \
     kernel-devel-%KERNEL_RELEASE%.rpm \
     kernel-modules-%KERNEL_RELEASE%.rpm

#RUN cd /usr/src/kernels/%KERNEL_RELEASE% &&\
#    make prepare

# Change this to trigger and effectively date/tag a full re-build
LABEL build="%CURRENT_DATESTAMP%"

# Create an updated image; improves build times
RUN yum -y update
