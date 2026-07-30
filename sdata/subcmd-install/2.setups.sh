# This script is meant to be sourced.
# It's not for directly running.

function prepare_systemd_user_service(){
  if [[ ! -e "/usr/lib/systemd/user/ydotool.service" ]]; then
    x sudo ln -s /usr/lib/systemd/{system,user}/ydotool.service
  fi
}

function setup_user_group(){
  if [[ -z $(getent group i2c) ]]; then
    x sudo groupadd i2c
  fi

  x sudo usermod -aG video,i2c,input "$(whoami)"
}
#####################################################################################
# These python packages are installed using uv into the venv (virtual environment). Once the folder of the venv gets deleted, they are all gone cleanly. So it's considered as setups, not dependencies.
showfun install-python-packages
v install-python-packages

showfun setup_user_group
v setup_user_group

if [[ ! -z $(systemctl --version) ]]; then
  v bash -c "echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf"
  if [[ ! "${INSTALL_VIA_NIX}" == true ]]; then
    if [[ ! -z "${DBUS_SESSION_BUS_ADDRESS}" ]]; then
      v systemctl --user enable ydotool --now
    else
      v sudo systemctl --machine=$(whoami)@.host --user enable ydotool --now
    fi
  fi
  v sudo systemctl enable bluetooth --now
elif [[ ! -z $(openrc --version) ]]; then
  v bash -c "echo 'modules=i2c-dev' | sudo tee -a /etc/conf.d/modules"
  v sudo rc-update add modules boot
  v sudo rc-update add ydotool default
  v sudo rc-update add bluetooth default

  x sudo rc-service ydotool start
  x sudo rc-service bluetooth start
else
  printf "${STY_RED}"
  printf "====================INIT SYSTEM NOT FOUND====================\n"
  printf "${STY_RST}"
  pause
fi

# Install hyprland-scroll-overview plugin via hyprpm
function setup_hyprpm_plugin(){
  if [[ "$OS_GROUP_ID" != "arch" ]]; then
    return 0
  fi

  if hyprpm list 2>/dev/null | grep -q "scrolloverview.*enabled"; then
    echo "scrolloverview plugin already installed and enabled, skipping."
    return 0
  fi

  echo "Setting up hyprpm for scrolloverview plugin..."
  x sudo mkdir -p /usr/share/hyprpm
  x sudo chown "$(whoami):$(whoami)" /usr/share/hyprpm

  if ! hyprpm list 2>/dev/null | grep -q "scrolloverview"; then
    echo "Adding scrolloverview plugin repository (git build branch)..."
    x hyprpm add https://github.com/yayuuu/hyprland-scroll-overview origin/new-release
    echo "Building plugin (this may take a while)..."
    x hyprpm update
  fi

  echo "Enabling scrolloverview plugin..."
  x hyprpm enable scrolloverview
  echo "scrolloverview plugin installed successfully."
}

showfun setup_hyprpm_plugin
v setup_hyprpm_plugin

v gsettings set org.gnome.desktop.interface font-name 'Google Sans Flex Medium 11 @opsz=11,wght=500'
v gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
v kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Darkly
