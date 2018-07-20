#!/bin/bash

set -e

trap_handleError() {
  echo "[ERROR] Trapped ERR signal."
}

run_clean() {
  local targetDir=${1:-"${_targetDir}"}

  if [[ -e ${targetDir} ]]; then
    echo "[INFO] Clean target dir: ${targetDir}"
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

}

log::infoBanner() {
  echo "##################################################"
  echo "## $1"
  echo "##################################################"
}

build_spl() {
  log::infoBanner "${FUNCNAME}"
  local kernelRelease=${1:-$(uname -r)}

  pushd ${_targetDir}/spl
      # Delete existing output files
      find . -name \*.ko -delete
	  
      # Now build it
      ./autogen.sh
      ./configure \
        --with-linux=/usr/src/kernels/${kernelRelease} \
        --with-linux-obj=/usr/src/kernels/${kernelRelease} \
	--enable-linux-builtin=yes 
      ./copy-builtin /usr/src/kernels/${kernelRelease}
      make -s -j$(nproc)
      make -j1 pkg-utils pkg-kmod module
  popd

}

build_zfs() {
  log::infoBanner "${FUNCNAME}"
  local kernelRelease=${1:-$(uname -r)}

  pushd ${_targetDir}/zfs
      # Delete existing output files
      find . -name \*.ko -delete
	  
      # Now build it
      ./autogen.sh
      ./configure \
        --with-linux=/usr/src/kernels/${kernelRelease} \
        --with-linux-obj=/usr/src/kernels/${kernelRelease}
#        --with-linux=/usr/lib/modules/${kernelRelease}/source \
#        --with-linux-obj=/usr/lib/modules/${kernelRelease}/build
      make -s -j$(nproc)
      make -j1 pkg-utils pkg-kmod
  popd

}

run_build() {
  local dockerFrom=${1:-"${_DOCKER_FROM_IMAGE_NAME}"}
  local kernelRelease
  kernelRelease=${2:-"$(uname -r)"}
  local dockerOutput
  
  pushd ${_targetDir}
      # Update/Get the spl source code
      if [[ -e spl ]]; then
        pushd spl
        git pull
        popd
      else
        git clone -b ${_SPL_BRANCH} https://github.com/zfsonlinux/spl.git
      fi

      # Update/Get the zfs source code
      if [[ -e zfs ]]; then
        pushd zfs
        git pull
        popd
      else
        git clone -b ${_ZFS_BRANCH} https://github.com/zfsonlinux/zfs.git
      fi
	  
  popd
	  
  docker run -it --rm \
      --workdir "/mnt/workspace/${_projectName}" \
      -v ${_workspaceDir}:/mnt/workspace \
      localhost/${dockerFrom}-${kernelRelease} \
      ./build-zfs.sh _build ${kernelRelease}
  
}

_run_build() {
  local kernelRelease
  kernelRelease=${1:-"$(uname -r)"}
  local processorType=${2:-'x86_64'}

  if ! command -v koji >/dev/null 2>&1; then
    echo "[ERROR] Missing command in docker image. Run '$0 dockerfile'"
	exit 1
  fi

  # TODO: Move to Dockerfile
  yum install -y file libtirpc-devel rpm-build 

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

build_dockerimage() {
  local targetDir=${_targetDir}
  local dockerFrom=${1:-"${_DOCKER_FROM_IMAGE_NAME}"}
  local kernelRelease
  kernelRelease=${2:-"$(uname -r)"}
  local dockerOutput
  
  local rpmCacheDir="${_rpmCacheDir}"

  echo "kernelRelease=${kernelRelease}"
  echo "rpmCacheDir=${rpmCacheDir}"

  pushd "${rpmCacheDir}"
    # Use koji to download the atomic kernel packages
    if [[ ! -e kernel-core-${kernelRelease}.rpm ]]; then 
      koji download-build --rpm --arch=${processorType} \
          kernel-core-${kernelRelease}
    fi
    cp kernel-core-${kernelRelease}.rpm ${targetDir}

    if [[ ! -e kernel-devel-${kernelRelease}.rpm ]]; then 
      koji download-build --rpm --arch=${processorType} \
          kernel-devel-${kernelRelease}
    fi
    cp kernel-devel-${kernelRelease}.rpm ${targetDir}

    if [[ ! -e kernel-modules-${kernelRelease}.rpm ]]; then 
      koji download-build --rpm --arch=${processorType} \
          kernel-modules-${kernelRelease}
    fi
    cp kernel-modules-${kernelRelease}.rpm ${targetDir}
  popd

  # Create Dockerfile staging dir
  if [[ ! -e ${targetDir}/Dockerfile ]]; then
    cp templates/Dockerfile ${targetDir}/
    sed -i "s/%DOCKER_FROM_IMAGE_NAME%/${dockerFrom}/" ${targetDir}/Dockerfile
    sed -i "s/%KERNEL_RELEASE%/${kernelRelease}/g" ${targetDir}/Dockerfile
  fi
 
  # Build Docker image from staging dir
  docker build -t localhost/${dockerFrom}-${kernelRelease} ${targetDir}

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
    'build_dockerimage')
      build_dockerimage "$@"
      ;;
    'build')
      run_build "$@"
      ;;
    '_build')
      _run_build "$@"
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
  local _rpmCacheDir

  _invocationDir=$(dirname $(realpath $0))
  _projectDir=${_invocationDir}
  _projectName=$(basename ${_projectDir})
  _workspaceDir=$(realpath ${_projectDir}/..)
  _targetDir=${_projectDir}/target
  _rpmCacheDir=${_workspaceDir}/.rpm_cache

  mkdir -p ${_rpmCacheDir}

  run_command "$@"
}

main_function "$@"

