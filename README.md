# openhost-bbs

A classic BBS for OpenHost, powered by [ENiGMA½](https://github.com/NuSkooler/enigma-bbs).

Deploy this on your OpenHost instance and you get:

- A telnet-reachable BBS on host port `2323`
- An SSH-reachable BBS on host port `2222`
- A web UI at `https://bbs.<your-zone>/`
- All the classic BBS machinery: message boards, file areas, door-game support, matrix/menu system

## Deploy

From the OpenHost dashboard, add app with the repo URL:

```
https://github.com/imbue-openhost/openhost-bbs
```

Grant the permissions it asks for (`app_data` — persistent storage for the user database, message base, and file areas). First boot takes a minute or two while it generates default themes and your sysop account.

## Logging in for the first time

The BBS generates a random sysop password on first run and writes it to:

```
/data/app_data/bbs/config/sysop-password.txt
```

inside the container. To read it, open a browser to the OpenHost file-browser app (or SSH in and `cat` the file) and grab the password. Then:

```
telnet <your-zone> 2323
```

or

```
ssh -p 2222 sysop@<your-zone>
```

Log in as `sysop` with the generated password, use the built-in "change password" menu, and **delete the `sysop-password.txt` file**.

## Customising

The BBS reads `config.hjson` from `/data/app_data/bbs/config/config.hjson`. The entrypoint writes a starter copy on first run and never touches it again — edit freely. See the [ENiGMA½ documentation](https://nuskooler.github.io/enigma-bbs/) for every available setting.

A few environment variables are baked into the generated starter config:

| Variable | Default | Notes |
|---|---|---|
| `BBS_BOARD_NAME` | `OpenHost BBS` | Shown at the login banner |
| `BBS_SYSOP_NAME` | `Sysop` | Real name for the sysop account |
| `BBS_SYSOP_LOCATION` | `cyberspace` | Shown on menus |
| `BBS_SYSOP_EMAIL` | `sysop@example.com` | For outbound mail |
| `BBS_DESCRIPTION` | `A BBS running on OpenHost` | One-line about |
| `BBS_WEBSITE` | _(empty)_ | Link in the menus |

These are only read on first run; once `config.hjson` exists, changing env vars has no effect. Edit the hjson directly.

## How the data layout works

ENiGMA expects to write to a handful of directories inside its install tree (`config/`, `db/`, `logs/`, `filebase/`, `mods/`, `art/`). The OpenHost container treats the install tree as immutable and replaces those directories with symlinks into `$OPENHOST_APP_DATA_DIR`. Result: the install is stateless (rebuilds safely) and all your data stays put across deploys, restarts, and app rebuilds.

```
$OPENHOST_APP_DATA_DIR/
├── config/            # config.hjson, SSH host keys, TLS cert material
│   ├── config.hjson
│   ├── security/ssh_host_key.pem
│   └── sysop-password.txt   # delete after first login
├── db/                # SQLite: users, messages, file base, stats
├── logs/              # rotating app log
├── filebase/          # hosted file areas
├── mods/              # your local mod overrides
└── art/               # themes and ANSI art
```

## Upgrading

The Dockerfile pins ENiGMA to a specific commit via `ARG ENIGMA_REF`. To upgrade:

1. Bump the commit hash in `Dockerfile`
2. Commit + push
3. In the OpenHost dashboard, click "Reload" on the bbs app with the update option checked

The data dir is preserved across upgrades. Only the immutable install tree gets replaced.

## What this isn't

- **Not a FidoNet hub.** ENiGMA speaks FidoNet and binkp, but configuring those is out of scope for the starter — see the ENiGMA docs under "message networks" if you want to federate.
- **Not door-game-ready.** Classic DOS doors need DOSEMU / DOSBox layered on top of the container; this image doesn't ship those. The mechanism ENiGMA uses for doors (`execute`) works for any unix-native door binary out of the box.
- **Not multi-node by default.** ENiGMA supports multiple simultaneous connections; the default config sets `maxConnections: 0` (unlimited), which is almost certainly fine for anything short of a community board. If you want actual node isolation / per-node configs, read ENiGMA's multi-node docs.

## Caveats

- `unrar-free` in Debian is lighter than the proprietary `unrar`; users uploading RAR5 archives may run into decompression errors. Swap to `unrar` if you can.
- The BBS binds raw TCP on the host's public IP. If you want telnet/SSH accessible only from a VPN, firewall the OpenHost host ports accordingly.
- First-run sysop password generation writes the plaintext password to a file. Delete the file after you log in once; otherwise the first person with filesystem access walks in with sysop credentials.
