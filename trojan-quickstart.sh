#!/bin/bash
set -euo pipefail

function prompt() {
    while true; do
        read -p "$1 [y/N] " yn
        case $yn in
            [Yy] ) return 0;;
            [Nn]|"" ) return 1;;
        esac
    done
}

function stopTrojan(){
    echo "Shutting down Trojan service."
    if [[ -n "${SYSTEMCTL_CMD}" ]] || [[ -f "/lib/systemd/system/trojan.service" ]] || [[ -f "/etc/systemd/system/trojan.service" ]]; then
        ${SYSTEMCTL_CMD} stop trojan
    elif [[ -n "${SERVICE_CMD}" ]] || [[ -f "/etc/init.d/trojan" ]]; then
        ${SERVICE_CMD} trojan stop
    fi
    if [[ $? -ne 0 ]]; then
        echo "Failed to shutdown Trojan service."
        return 2
    fi
    return 0
}

function startTrojan(){
    if [ -n "${SYSTEMCTL_CMD}" ] && [[ -f "/lib/systemd/system/trojan.service" || -f "/etc/systemd/system/trojan.service" ]]; then
        ${SYSTEMCTL_CMD} start trojan
    elif [ -n "${SERVICE_CMD}" ] && [ -f "/etc/init.d/trojan" ]; then
        ${SERVICE_CMD} trojan start
    fi
    if [[ $? -ne 0 ]]; then
        echo "Failed to start Trojan service."
        return 2
    fi
    return 0
}

if [[ $(id -u) != 0 ]]; then
    echo Please run this script as root.
    exit 1
fi

if [[ $(uname -m 2> /dev/null) != x86_64 ]]; then
    echo Please run this script on x86_64 machine.
    exit 1
fi

NAME=trojan
[[ -f /usr/local/bin/trojan ]] && VER="$(/usr/local/bin/trojan -v 2>&1)" && CUR_VER=$(echo $VER | grep -i "^welcome" |sed 's|^\(Welcome to trojan \)\([0-9]*\.[0-9]*\.[0-9]*$\)|\2|') || CUR_VER=Null;
NEW_VER=`curl -s https://api.github.com/repos/trojan-gfw/$NAME/releases/latest | grep 'tag_name' | cut -d\" -f4 | awk -F "v" '{print $2}'`

if [[ $NEW_VER == $CUR_VER ]];then
    echo "Already the latest version.";
    exit    0;
fi

TARBALL="$NAME-$NEW_VER-linux-amd64.tar.xz"
DOWNLOADURL="https://github.com/trojan-gfw/$NAME/releases/download/v$NEW_VER/$TARBALL"
TMPDIR="$(mktemp -d)"
INSTALLPREFIX=/usr/local
SYSTEMDPREFIX=/etc/systemd/system
SYSTEMCTL_CMD=$(command -v systemctl 2>/dev/null)
SERVICE_CMD=$(command -v service 2>/dev/null)

BINARYPATH="$INSTALLPREFIX/bin/$NAME"
CONFIGPATH="$INSTALLPREFIX/etc/$NAME/config.json"
SYSTEMDPATH="$SYSTEMDPREFIX/$NAME.service"

OWCONFIG=False
OWSYSTEMDPREFIX=True

echo Entering temp directory $TMPDIR...
cd "$TMPDIR"

echo Downloading $NAME $NEW_VER...
curl -LO --progress-bar "$DOWNLOADURL" || wget -q --show-progress "$DOWNLOADURL"

echo Unpacking $NAME $NEW_VER...
tar xf "$TARBALL"
cd "$NAME"

echo Installing $NAME $NEW_VER to $BINARYPATH...
install -Dm755 "$NAME" "$BINARYPATH"

echo Installing $NAME server config to $CONFIGPATH...
if ! [[ -f "$CONFIGPATH" ]] || $OWCONFIG "The server config already exists in $CONFIGPATH, overwrite?"; then
    install -Dm644 examples/server.json-example "$CONFIGPATH"
else
    echo Skipping installing $NAME server config...
fi

if [[ -d "$SYSTEMDPREFIX" ]]; then
    echo Installing $NAME systemd service to $SYSTEMDPATH...
    if ! [[ -f "$SYSTEMDPATH" ]] || $OWSYSTEMDPREFIX "The systemd service already exists in $SYSTEMDPATH, overwrite?"; then
        cat > "$SYSTEMDPATH" << EOF
[Unit]
Description=$NAME
Documentation=https://trojan-gfw.github.io/$NAME/config https://trojan-gfw.github.io/$NAME/
After=network.target network-online.target nss-lookup.target mysql.service mariadb.service mysqld.service

[Service]
Type=simple
StandardError=journal
ExecStart="$BINARYPATH" "$CONFIGPATH"
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF
        echo Reloading systemd daemon...
        systemctl daemon-reload
    else
        echo Skipping installing $NAME systemd service...
    fi
fi

echo Deleting temp directory $TMPDIR...
rm -rf "$TMPDIR"

stopTrojan
startTrojan

echo Done!
