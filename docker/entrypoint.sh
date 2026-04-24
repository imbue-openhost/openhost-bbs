#!/usr/bin/env bash
# Entrypoint for the OpenHost-packaged ENiGMA½ BBS.
#
# Each setup step below is idempotent and gated on a specific file,
# not on a single "first run" flag. That means if we add a new step
# (e.g. generate a new config fragment ENiGMA started requiring) in a
# later release, existing installs pick it up on next restart without
# losing their user data.

set -euo pipefail

BBS_ROOT=${BBS_ROOT:-/enigma-bbs}
BBS_STAGING=${BBS_STAGING:-/enigma-pre}

# OpenHost provides OPENHOST_APP_DATA_DIR when app_data=true in the
# manifest. Fall back to a sensible default for local testing.
DATA_DIR=${OPENHOST_APP_DATA_DIR:-/enigma-data}

echo "[bbs] data dir: ${DATA_DIR}"

mkdir -p "${DATA_DIR}"

# -----------------------------------------------------------------
# Runtime-writable dirs: symlinked from the install tree to the
# persistent data dir.
# -----------------------------------------------------------------
RUNTIME_DIRS=(config db logs filebase mods art)
for d in "${RUNTIME_DIRS[@]}"; do
    host_path="${DATA_DIR}/${d}"
    mkdir -p "${host_path}"
    if [ -e "${BBS_ROOT}/${d}" ] && [ ! -L "${BBS_ROOT}/${d}" ]; then
        rm -rf "${BBS_ROOT}/${d}"
    fi
    rm -f "${BBS_ROOT}/${d}"
    ln -s "${host_path}" "${BBS_ROOT}/${d}"
done

# -----------------------------------------------------------------
# Seed config, mods, art from staging if empty.
# -----------------------------------------------------------------
seed_from_staging() {
    local name=$1
    local src="${BBS_STAGING}/${name}"
    local dst="${DATA_DIR}/${name}"
    if [ -d "${src}" ] && [ -z "$(ls -A "${dst}" 2>/dev/null)" ]; then
        echo "[bbs] seeding ${name} from staging"
        cp -rp "${src}/." "${dst}/"
    fi
}
for d in config mods art; do
    seed_from_staging "${d}"
done

# -----------------------------------------------------------------
# Board-name-derived slug used for menu filenames. Must match what
# ENiGMA's oputil would generate for the same board name — see
# core/oputil/oputil_config.js's sanatizeFilename + substitutions.
# -----------------------------------------------------------------
board_slug() {
    echo "${1}" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9_-]\+/_/g; s/_\+/_/g; s/^_//; s/_$//'
}
BOARD_NAME_SLUG=$(board_slug "${BBS_BOARD_NAME:-OpenHost BBS}")
[ -z "${BOARD_NAME_SLUG}" ] && BOARD_NAME_SLUG="openhost_bbs"

# -----------------------------------------------------------------
# Menu file assembly.
# Gated on the main menu file's existence, independent of
# config.hjson. This means existing installs that somehow ended up
# with a config but no menus will self-heal on next restart.
# -----------------------------------------------------------------
MENUS_DIR="${DATA_DIR}/config/menus"
MAIN_MENU_FILE="${MENUS_DIR}/${BOARD_NAME_SLUG}-main.hjson"

if [ ! -f "${MAIN_MENU_FILE}" ]; then
    echo "[bbs] assembling menu files under ${MENUS_DIR}"
    mkdir -p "${MENUS_DIR}"

    INCLUDE_TEMPLATES=(
        message_base.in.hjson
        private_mail.in.hjson
        login.in.hjson
        new_user.in.hjson
        doors.in.hjson
        file_base.in.hjson
        activitypub.in.hjson
    )
    INCLUDE_NAMES=()
    for tpl in "${INCLUDE_TEMPLATES[@]}"; do
        out_name="${BOARD_NAME_SLUG}-${tpl%.in.hjson}.hjson"
        # -n: don't clobber if it already exists. Operator edits win.
        cp -n "${BBS_ROOT}/misc/menu_templates/${tpl}" "${MENUS_DIR}/${out_name}"
        INCLUDE_NAMES+=("${out_name}")
    done

    MAIN_TEMPLATE="${BBS_ROOT}/misc/menu_templates/main.in.hjson"

    # Build the include block — list of include filenames joined by
    # newline + two tabs — and substitute for %INCLUDE_FILES% in
    # main.in.hjson, matching what ``oputil config new`` does.
    INCLUDE_BLOCK=""
    for inc in "${INCLUDE_NAMES[@]}"; do
        if [ -z "${INCLUDE_BLOCK}" ]; then
            INCLUDE_BLOCK="${inc}"
        else
            INCLUDE_BLOCK=$(printf '%s\n\t\t%s' "${INCLUDE_BLOCK}" "${inc}")
        fi
    done
    export INCLUDE_BLOCK

    awk '
        /%INCLUDE_FILES%/ {
            idx = index($0, "%INCLUDE_FILES%")
            printf "%s", substr($0, 1, idx - 1)
            printf "%s", ENVIRON["INCLUDE_BLOCK"]
            printf "%s\n", substr($0, idx + length("%INCLUDE_FILES%"))
            next
        }
        { print }
    ' "${MAIN_TEMPLATE}" > "${MAIN_MENU_FILE}"
fi

# -----------------------------------------------------------------
# SSH host key.
# -----------------------------------------------------------------
SSH_HOST_KEY="${DATA_DIR}/config/security/ssh_host_key.pem"
if [ ! -f "${SSH_HOST_KEY}" ]; then
    echo "[bbs] generating SSH host key"
    mkdir -p "${DATA_DIR}/config/security"
    ssh-keygen -q -t ed25519 -N "" -m pem \
        -f "${SSH_HOST_KEY}" \
        -C "openhost-bbs-$(date +%Y%m%d)"
    chmod 600 "${SSH_HOST_KEY}"
fi

# -----------------------------------------------------------------
# Starter config.hjson + first-run README.
# -----------------------------------------------------------------
CONFIG_FILE="${DATA_DIR}/config/config.hjson"

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "[bbs] writing starter config.hjson"

    cat > "${CONFIG_FILE}" <<HJSON
{
    //  ENiGMA 1/2 BBS — generated by openhost-bbs entrypoint.sh
    //  Edit freely; this file is not regenerated on restart.

    general: {
        boardName: "${BBS_BOARD_NAME:-OpenHost BBS}"
        prettyBoardName: "|09Open|15Host |13BBS"
        //  Path to the main menu file the entrypoint assembled
        //  from the upstream menu_templates. Must live where
        //  paths.config (below) plus "/menus" points, so ENiGMA
        //  can resolve includes relative to it.
        menuFile: "/enigma-bbs/config/menus/${BOARD_NAME_SLUG}-main.hjson"
        sysOp: {
            username: "sysop"
            realName: "${BBS_SYSOP_NAME:-Sysop}"
            location: "${BBS_SYSOP_LOCATION:-cyberspace}"
            affiliations: "ENiGMA½ on OpenHost"
            email: "${BBS_SYSOP_EMAIL:-sysop@example.com}"
        }
        description: "${BBS_DESCRIPTION:-A BBS running on OpenHost}"
        website: "${BBS_WEBSITE:-}"
    }

    loginServers: {
        telnet: {
            enabled: true
            port: 8888
        }
        ssh: {
            enabled: true
            port: 8889
            privateKeyPem: /enigma-bbs/config/security/ssh_host_key.pem
            privateKeyPass: ""
            algorithms: {
                kex:
                    [
                        curve25519-sha256
                        curve25519-sha256@libssh.org
                        ecdh-sha2-nistp256
                        ecdh-sha2-nistp384
                        ecdh-sha2-nistp521
                        diffie-hellman-group-exchange-sha256
                        diffie-hellman-group14-sha256
                        diffie-hellman-group16-sha512
                        diffie-hellman-group18-sha512
                        diffie-hellman-group14-sha1
                    ]
                cipher:
                    [
                        aes128-ctr
                        aes192-ctr
                        aes256-ctr
                        aes128-gcm@openssh.com
                        aes256-gcm@openssh.com
                    ]
                hmac:
                    [
                        hmac-sha2-256-etm@openssh.com
                        hmac-sha2-512-etm@openssh.com
                        hmac-sha1-etm@openssh.com
                        hmac-sha2-256
                        hmac-sha2-512
                        hmac-sha1
                    ]
                compress:
                    [
                        none
                    ]
            }
        }
    }

    contentServers: {
        web: {
            //  HTTP enabled on 8080 so the OpenHost router (which
            //  terminates TLS externally and proxies http-to-http
            //  internally) has a real backend to hit. HTTPS is
            //  disabled here — certificate provisioning is the
            //  router's job, not ENiGMA's.
            http: {
                enabled: true
                port: 8080
            }
            https: {
                enabled: false
            }
        }
    }

    paths: {
        //  Pinned runtime paths (matching the entrypoint's symlinks).
        config: /enigma-bbs/config/
        security: /enigma-bbs/config/security/
        mods: /enigma-bbs/mods/
        db: /enigma-bbs/db/
        modsDb: /enigma-bbs/db/mods/
        logs: /enigma-bbs/logs/
        fileBase: /enigma-bbs/filebase/
    }
}
HJSON
    chmod 644 "${CONFIG_FILE}"

    # Drop a welcome note so operators know how to finish setup. We
    # don't create the sysop account here because ENiGMA has no
    # non-interactive "user add" command — the first user to register
    # via telnet/SSH (with the default newUserNames = ["new", "apply"])
    # becomes user ID 1, which is the sysop.
    cat > "${DATA_DIR}/config/first-run-readme.txt" <<EOF
ENiGMA½ BBS first-run setup
---------------------------

To claim your sysop account:

  1. Connect via telnet or SSH (see host ports in openhost.toml).
  2. At the username prompt, enter "new" (or "apply").
  3. Follow the new-user application flow.
  4. The FIRST user to register is automatically the sysop.

Any later registrations become regular users.

If you'd like to reset or change the sysop password later, exec into
the container and run:

    node /enigma-bbs/oputil.js user pw <username>

To list all users:

    node /enigma-bbs/oputil.js user list

Delete this file once setup is complete.
EOF
    chmod 644 "${DATA_DIR}/config/first-run-readme.txt"
fi

echo "[bbs] setup done — handing off to ENiGMA"

# exec so signals reach the Node process directly — no pm2, no bash
# between us and it.
exec "$@"
