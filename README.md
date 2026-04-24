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

Grant the permissions it asks for (`app_data` — persistent storage for the user database, message base, and file areas). First boot takes a minute or two while it seeds default themes, menus, and config.

## Claiming your sysop account

ENiGMA has no non-interactive "create user" command, so the first-run entrypoint doesn't pre-create an admin for you. Instead, the first user to register through the new-user flow becomes user ID 1, which is the sysop.

On first deploy:

1. Connect via telnet:

   ```
   telnet <your-zone> 2323
   ```

   or SSH:

   ```
   ssh -p 2222 new@<your-zone>
   ```

2. At the username prompt, enter `new` (or `apply`). These names are reserved by ENiGMA for kicking off new-user registration.

3. Follow the new-user application — pick your sysop username, password, real name, etc.

4. You're logged in as sysop. Read `first-run-readme.txt` inside the app data dir for a reminder of these steps, and delete it once you've claimed the account.

Any later registrations become regular users with the default `users` group. Promote/demote users with `node /enigma-bbs/oputil.js user group <name> +sysops` from inside the container.

## Customising

The BBS reads `config.hjson` from `/data/app_data/bbs/config/config.hjson`. The entrypoint writes a starter copy on first run and never touches it again — edit freely. See the [ENiGMA½ documentation](https://nuskooler.github.io/enigma-bbs/) for every available setting.

A few environment variables are baked into the generated starter config:

| Variable | Default | Notes |
|---|---|---|
| `BBS_BOARD_NAME` | `OpenHost BBS` | Shown at the login banner |
| `BBS_SYSOP_NAME` | `Sysop` | Display name of the sysop on menus (different from the sysop's BBS username, which you pick when you register) |
| `BBS_SYSOP_LOCATION` | `cyberspace` | Shown on menus |
| `BBS_SYSOP_EMAIL` | `sysop@example.com` | For outbound mail |
| `BBS_DESCRIPTION` | `A BBS running on OpenHost` | One-line about |
| `BBS_WEBSITE` | _(empty)_ | Link in the menus |

These are only read on first run; once `config.hjson` exists, changing env vars has no effect. Edit the hjson directly.

## How the data layout works

ENiGMA expects to write to a handful of directories inside its install tree (`config/`, `db/`, `logs/`, `filebase/`, `mods/`, `art/`). The OpenHost container treats the install tree as immutable and replaces those directories with symlinks into `$OPENHOST_APP_DATA_DIR`. Result: the install is stateless (rebuilds safely) and all your data stays put across deploys, restarts, and app rebuilds.

```
$OPENHOST_APP_DATA_DIR/
├── config/            # config.hjson, SSH host keys, menu hjsons
│   ├── config.hjson
│   ├── menus/<board>-main.hjson (+ include fragments)
│   ├── security/ssh_host_key.pem
│   └── first-run-readme.txt   # delete after claiming sysop
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
- There's a first-to-register-wins window where anyone reaching the BBS before you can grab the sysop account. Deploy and claim immediately, or block port 2323/2222 at the firewall until you've registered.
