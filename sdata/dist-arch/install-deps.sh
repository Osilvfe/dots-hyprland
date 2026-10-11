# This script is meant to be sourced.
# It's not for directly running.

install-paru(){
  x sudo pacman -S --needed --noconfirm base-devel git
  x git clone https://aur.archlinux.org/paru-bin.git /tmp/buildparu
  x cd /tmp/buildparu
  x makepkg -si --noconfirm
  x cd ${REPO_ROOT}
  rm -rf /tmp/buildparu
}

install-yay(){
  x sudo pacman -S --needed --noconfirm base-devel git
  x git clone https://aur.archlinux.org/yay-bin.git /tmp/buildyay
  x cd /tmp/buildyay
  x makepkg -si --noconfirm
  x cd ${REPO_ROOT}
  rm -rf /tmp/buildyay
}

remove_deprecated_dependencies(){
  printf "${STY_CYAN}[$0]: Removing deprecated dependencies and conflicting official packages:${STY_RST}\n"
  local list=()
  list+=(illogical-impulse-{microtex,pymyc-aur,oneui4-icons-git})
  list+=(hyprland-qtutils)
  list+=(hyprland-git)
  list+=({hyprpicker,hypridle,hyprland-qt-support,hyprland-qtutils,hyprlock,xdg-desktop-portal-hyprland}-git)
  list+=(matugen-bin)
  # Remove official repository packages that conflict with our customized/git components,
  # ensuring that the correct replacements can be installed cleanly without conflict prompts.
  list+=(hyprland xorg-xwayland hyprutils hyprlang hyprgraphics hyprcursor aquamarine hyprwayland-scanner quickshell)
  for i in "${list[@]}"; do try sudo pacman --noconfirm -Rdd "$i"; done
}
# NOTE: `implicitize_old_dependencies()` was for the old days when we just switch from dependencies.conf to local PKGBUILDs.
# However, let's just keep it as references for other distros writing their `sdata/dist-<OS_GROUP_ID>/install-deps.sh`, if they need it.
implicitize_old_dependencies(){
# Convert old dependencies to non explicit dependencies so that they can be orphaned if not in meta packages
  remove_bashcomments_emptylines ./sdata/dist-arch/previous_dependencies.conf ./cache/old_deps_stripped.conf
  readarray -t old_deps_list < ./cache/old_deps_stripped.conf
  pacman -Qeq > ./cache/pacman_explicit_packages
  readarray -t explicitly_installed < ./cache/pacman_explicit_packages

  echo "Attempting to set previously explicitly installed deps as implicit..."
  for i in "${explicitly_installed[@]}"; do for j in "${old_deps_list[@]}"; do
    [ "$i" = "$j" ] &&   sudo pacman -D --asdeps "$i"
  done; done

  return 0
}

#####################################################################################
if ! command -v pacman >/dev/null 2>&1; then
  printf "${STY_RED}[$0]: pacman not found, it seems that the system is not ArchLinux or Arch-based distros. Aborting...${STY_RST}\n"
  exit 1
fi

# Keep makepkg from resetting sudo credentials
if [[ -z "${PACMAN_AUTH:-}" ]]; then
  export PACMAN_AUTH="sudo"
fi

showfun remove_deprecated_dependencies
v remove_deprecated_dependencies

# Issue #363
case $SKIP_SYSUPDATE in
  true) true;;
  *) v sudo pacman -Syu;;
esac

# Detect or install AUR helper (paru or yay)
if command -v paru >/dev/null 2>&1; then
  AUR_HELPER="paru"
elif command -v yay >/dev/null 2>&1; then
  AUR_HELPER="yay"
else
  echo -e "${STY_YELLOW}[$0]: Neither \"paru\" nor \"yay\" was found.${STY_RST}"
  if [[ "${MACHINE_ARCH}" == "aarch64" ]]; then
    showfun install-yay
    v install-yay
    AUR_HELPER="yay"
  else
    showfun install-paru
    v install-paru
    AUR_HELPER="paru"
  fi
fi
echo -e "${STY_GREEN}[$0]: Using \"${AUR_HELPER}\" as AUR helper.${STY_RST}"

showfun implicitize_old_dependencies
v implicitize_old_dependencies

# https://github.com/end-4/dots-hyprland/issues/581
# paru/yay -Bi is kinda hit or miss, instead cd into the relevant directory and manually source and install deps
install-local-pkgbuild() {
  local location=$1
  local installflags=$2

  x pushd $location

  source ./PKGBUILD

  # If --needed is specified and the package is already installed, skip building and reinstalling
  local pkgs=("${pkgname[@]}")
  local all_installed=true
  for p in "${pkgs[@]}"; do
    if ! pacman -Q "$p" >/dev/null 2>&1; then
      all_installed=false
      break
    fi
  done
  if [[ "$installflags" =~ "--needed" && "$all_installed" == true ]]; then
    echo -e "${STY_GREEN}[$0]: Package \"${pkgs[*]}\" is already installed, skipping building...${STY_RST}"
    x popd
    return 0
  fi

  local build_deps=("${depends[@]}")
  if [[ -n "${makedepends[*]:-}" ]]; then
    build_deps+=("${makedepends[@]}")
  fi

  local root_dir="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  local external_deps=()

  for dep in "${build_deps[@]}"; do
    local dep_name="${dep%%[<>=]*}"

    # 1. Skip if already satisfied by an installed package
    if pacman -T "$dep" >/dev/null 2>&1; then
      continue
    fi

    # 2. Check if dependency is a local package in our repository
    local local_dir="${root_dir}/sdata/dist-arch/${dep_name}"
    if [[ -d "$local_dir" && -f "$local_dir/PKGBUILD" ]]; then
      echo -e "${STY_CYAN}[$0]: Dependency \"${dep_name}\" is a local package. Building locally...${STY_RST}"
      install-local-pkgbuild "$local_dir" "$installflags"
    else
      # 3. Otherwise, it is an external dependency from repo/AUR
      external_deps+=("$dep")
    fi
  done

  # Only call AUR helper if there are missing external dependencies
  if [[ ${#external_deps[@]} -gt 0 ]]; then
    local extra_aur_flags=()
    if [[ "${AUR_HELPER}" == "yay" || "${AUR_HELPER}" == "paru" ]]; then
      extra_aur_flags+=(--useask)
    fi
    extra_aur_flags+=(--ask 4)
    if [[ "${MACHINE_ARCH}" == "aarch64" ]]; then
      extra_aur_flags+=(--mflags="--ignorearch")
    fi
    x $AUR_HELPER -S --sudoloop $installflags "${extra_aur_flags[@]}" --asdeps "${external_deps[@]}"
  fi

  # Build the package locally using makepkg (without -i to avoid default conflict rejection)
  x makepkg -CAfs --noconfirm

  # Accurately resolve built package files using makepkg --packagelist
  local built_targets=()
  while IFS= read -r pkgfile; do
    if [[ -f "$pkgfile" && "$pkgfile" != *-debug-* ]]; then
      built_targets+=("$pkgfile")
    fi
  done < <(makepkg --packagelist 2>/dev/null || true)

  # Fallback if --packagelist produced no files
  if [[ ${#built_targets[@]} -eq 0 ]]; then
    for f in *.pkg.tar.*; do
      if [[ -f "$f" && "$f" != *-debug-* ]]; then
        built_targets+=("$f")
      fi
    done
  fi

  if [[ ${#built_targets[@]} -gt 0 ]]; then
    # Install built package with --ask 4 so that any package conflict automatically chooses 'yes' to replace
    x sudo pacman -U $installflags --ask 4 "${built_targets[@]}"
  else
    echo -e "${STY_RED}[$0]: No built package found in $location!${STY_RST}"
    x popd
    return 1
  fi

  x popd
}

# Install core dependencies from the meta-packages
# Order matters: install core customized replacement providers FIRST (hyprland and quickshell)
# so that subsequent packages that depend on 'hyprland' or 'quickshell' won't accidentally
# trigger installation of conflicting upstream packages beforehand.
metapkgs=(
  ./sdata/dist-arch/hyprland-hidpi-xprop-moetayuko
  ./sdata/dist-arch/illogical-impulse-quickshell-git
  ./sdata/dist-arch/illogical-impulse-hyprland
  ./sdata/dist-arch/illogical-impulse-microtex-git
  ./sdata/dist-arch/illogical-impulse-bibata-modern-classic-bin
  ./sdata/dist-arch/illogical-impulse-{audio,backlight,basic,fonts-themes,kde,portal,python,screencapture,toolkit,widgets}
)

for i in "${metapkgs[@]}"; do
  metainstallflags="--needed"
  $ask && showfun install-local-pkgbuild || metainstallflags="$metainstallflags --noconfirm"
  v install-local-pkgbuild "$i" "$metainstallflags"
done

## Optional dependencies
if pacman -Qs ^plasma-browser-integration$ ;then SKIP_PLASMAINTG=true;fi
case $SKIP_PLASMAINTG in
  true) true;;
  *)
    if $ask;then
      echo -e "${STY_YELLOW}[$0]: NOTE: The size of \"plasma-browser-integration\" is ~600 KiB, but if you don't yet have KDE on your system it'll pull an extra ~600MiB of packages.${STY_RST}"
      echo -e "${STY_YELLOW}It is needed if you want playtime of media in Firefox to be shown on the music controls widget.${STY_RST}"
      echo -e "${STY_YELLOW}Install it? [y/N]${STY_RST}"
      read -p "====> " p
    else
      p=y
    fi
    case $p in
      y) x sudo pacman -S --needed --noconfirm plasma-browser-integration ;;
      *) echo "Ok, won't install"
    esac
    ;;
esac
