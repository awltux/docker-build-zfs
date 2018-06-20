#!/bin/bash

set -e

trap_handleError() {
  echo "[ERROR] Trapped ERR signal."
}

run_clean() {
  local targetDir=${1:-"${_targetDir}"}

  if [[ -e ${targetDir} ]]; then
    echo "[INFO] Clean target dir: ${targetDir} "
    if [[ -e ${targetDir}/.target ]]; then
      read -n 1 -p "Press any key to continue"
      rm -rf ${targetDir}
    fi
  fi
  mkdir -p ${targetDir}
  touch ${targetDir}/.target

  # spl git checkout is in the workspace
  if [[ -e ${targetDir}/spl ]]; then
    pushd ${targetDir}/spl
      make distclean	  
    popd
  fi

  # zfs git checkout is in the workspace
  if [[ -e ${targetDir}/zfs ]]; then
    pushd ${targetDir}/zfs
      make distclean	  
    popd
  fi

  dnf clean all
  
}

run_dockerfile() {
    
#  yum groupinstall -y "Development Tools"
#  yum install -y \
#    koji autoconf automake libtool wget libtirpc-devel rpm-build \
#    zlib-devel libuuid-devel libattr-devel \
#    libblkid-devel libselinux-devel libudev-devel \
#    parted lsscsi ksh openssl-devel elfutils-libelf-devel
    
  yum groupinstall -y "C Development Tools and Libraries"
  yum install -y \
     koji \
     zlib-devel libuuid-devel libattr-devel \
     libblkid-devel libselinux-devel libudev-devel \
     parted lsscsi ksh openssl-devel elfutils-libelf-devel
}

install_kernelPackages() {
  local kernelRelease=${1:-$(uname -r)}
  local rpmCacheDir="~/.rpm_cache"

  pushd "${rpmCacheDir}"
      # Use koji to download the atomic kernel packages
      if [[ ! -e kernel-core-${kernelRelease}.rpm ]]; then 
        koji download-build --rpm --arch=${processorType} \
            kernel-core-${kernelRelease}
      fi
      if [[ ! -e kernel-devel-${kernelRelease}.rpm ]]; then 
        koji download-build --rpm --arch=${processorType} \
            kernel-devel-${kernelRelease}
      fi
      if [[ ! -e kernel-modules-${kernelRelease}.rpm ]]; then 
        koji download-build --rpm --arch=${processorType} \
            kernel-modules-${kernelRelease}
      fi
      dnf install -y --cacheonly \
            kernel-core-${kernelRelease}.rpm \
            kernel-devel-${kernelRelease}.rpm \
            kernel-modules-${kernelRelease}.rpm
  popd

  pushd ${_targetDir}
      # Use koji to download the atomic kernel packages
      if [[ ! -e kernel-core-${kernelRelease}.rpm ]]; then 
        cp ${rpmCacheDir}/kernel-core-${kernelRelease}.rpm .
      fi
      if [[ ! -e kernel-devel-${kernelRelease}.rpm ]]; then 
        cp ${rpmCacheDir}/kernel-devel-${kernelRelease}.rpm .
      fi
      if [[ ! -e kernel-modules-${kernelRelease}.rpm ]]; then 
        cp ${rpmCacheDir}/kernel-modules-${kernelRelease}.rpm .
      fi
      dnf install -y --cacheonly \
            kernel-core-${kernelRelease}.rpm \
            kernel-devel-${kernelRelease}.rpm \
            kernel-modules-${kernelRelease}.rpm
  popd

  pushd /usr/src/kernels/${kernelRelease}
    make prepare
  popd
}

build_spl() {
  local kernelRelease=${1:-$(uname -r)}

  pushd ${_targetDir}
      # Update/Get the spl source code
      if [[ -e spl ]]; then
        pushd spl
        git pull
      else
        git clone -b ${_SPL_BRANCH} https://github.com/zfsonlinux/spl.git
        pushd spl
      fi
	  
	  # Delete existing output files
      find . -name \*.ko -delete
	  
      # Now build it
      ./autogen.sh
      ./configure \
        --with-linux=/usr/src/kernels/${kernelRelease} \
		--enable-linux-builtin 
      ./copy-builtin /usr/src/kernels/${kernelRelease}
  popd

}

build_zfs() {
  local kernelRelease=${1:-$(uname -r)}

  pushd ${_targetDir}
      # Update/Get the zfs source code
      if [[ -e zfs ]]; then
        pushd zfs
        git pull
      else
        git clone -b ${_ZFS_BRANCH} https://github.com/zfsonlinux/zfs.git
        pushd zfs
      fi
	  
	  # Delete existing output files
      find . -name \*.ko -delete
	  
      # Now build it
      ./autogen.sh
      ./configure \
        --with-linux=/usr/lib/modules/${kernelRelease}/source \
        --with-linux-obj=/usr/lib/modules/${kernelRelease}/build
      make -s -j$(nproc)
      make -j1 pkg-utils pkg-kmod
  popd

}

run_build() {
  local kernelRelease=${1:-$(uname -r)}
  local processorType=${2:-'x86_64'}

  if ! command -v koji >/dev/null 2>&1; then
    echo "[ERROR] Missing command in docker image. Run '$0 dockerfile'"
	exit 1
  fi

  install_kernelPackages ${kernelRelease}
  build_spl ${kernelRelease}
  build_zfs ${kernelRelease}
  
  
}

run_all() {
  local targetDir=${_targetDir}
  
  run_clean ${targetDir}
  run_dockerfile
  run_build "$@"
}


show_help() {
  cat <<HEREDOC
Usage: 
  $0 <command> <commandProperties>
Commands:
  all 
  clean
  dockerfile
  build
  help
  
HEREDOC
}

build_dockerfile() {
  local targetDir=${_targetDir}
  local dockerFrom=${1:-"${_DOCKER_FROM_IMAGE_NAME}"}
  local dockerOutput
  
  cp templates/Dockerfile ${targetDir}/
  sed -i "s/%DOCKER_FROM_IMAGE_NAME%/${_DOCKER_FROM_IMAGE_NAME}/" ${targetDir}/Dockerfile
  cp $0 ${targetDir}/
 
  docker build -t test-${_DOCKER_FROM_IMAGE_NAME} ${targetDir}
  
#  dockerOutput=$(docker run -it --rm -v /root:/root ${dockerFrom} /bin/bash)

}

run_command() {
  local _RELEASE_BRANCH=${RELEASE_BRANCH:-'0.7-release'}
  local _ZFS_BRANCH=${ZFS_BRANCH:-"zfs-${_RELEASE_BRANCH}"}
  local _SPL_BRANCH=${SPL_BRANCH:-"spl-${_RELEASE_BRANCH}"}
  local _DOCKER_FROM_IMAGE_NAME='fedora:28'

  case "${_scriptCommand}" in
    'all')
      run_all "$@"
      ;;
    'clean')
      run_clean "$@"
      ;;
    'build_dockerfile')
      build_dockerfile "$@"
      ;;
    '_build_dockerfile')
      run_dockerfile "$@"
      ;;
    'build')
      run_build "$@"
      ;;
    'build_spl')
      build_spl "$@"
      ;;
    'build_zfs')
      build_zfs "$@"
      ;;
    'help')
      show_help "$@"
      ;;
    *)
      if [[ -z "${_scriptCommand}" ]]; then
        echo "[ERROR] Missing scriptCommand."
      else
        echo "[ERROR] Invalid scriptCommand: ${_scriptCommand}"
      fi
      show_help
      exit 1
      ;;
  esac    
}

# Generic landing function; all scripts have one of these
main_function() {
  local _scriptCommand
  if [[ -n "$1" ]]; then
    _scriptCommand=$1
    shift
  fi

  trap trap_handleError ERR

  local _invocationDir
  local _projectDir
  local _workspaceDir
  local _targetDir
  _invocationDir=$(dirname $(realpath $0))
  _projectDir=${_invocationDir}
  _workspaceDir=$(realpath ${_projectDir}/..)
  _targetDir=${_projectDir}/target

  run_command "$@"
}

main_function "$@"

