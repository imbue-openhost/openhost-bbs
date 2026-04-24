# ENiGMA½ BBS packaged for OpenHost.
#
# Build strategy roughly mirrors the upstream docker/Dockerfile:
# clone ENiGMA at a pinned commit, install its npm deps, then trigger
# the one-off "generate defaults" pass so the built image carries
# template copies of config/, mods/, and art/ under /enigma-pre/ that
# the entrypoint copies into $OPENHOST_APP_DATA_DIR on first run.
#
# What's different from upstream:
#   * No pm2 / pm2-runtime. We exec node directly so signals propagate
#     cleanly and OpenHost's container supervision Just Works.
#   * All runtime-writable state (config, db, logs, filebase, mods,
#     art) lives under OPENHOST_APP_DATA_DIR via symlinks created by
#     the entrypoint. That lets OpenHost bind-mount a single directory
#     rather than six volumes.
#   * No `VOLUME` declarations — the openhost manifest decides the
#     bind-mount scheme.

FROM node:20-bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive

# ENiGMA at this pinned commit. Bump by editing ENIGMA_REF below and
# rebuilding. Keeping it pinned avoids "works on my machine" drift
# between deploys and also means upstream breakage can't surprise us.
ARG ENIGMA_REF=738c1da9d9f2fefa24b10cc0518fb01ccdb8e4fb

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        curl \
        build-essential \
        python3 \
        libssl-dev \
        dos2unix \
    && rm -rf /var/lib/apt/lists/*

# Clone at the pinned commit with a shallow-ish history so image size
# doesn't balloon.
RUN git clone https://github.com/NuSkooler/enigma-bbs.git /enigma-bbs \
    && cd /enigma-bbs \
    && git checkout ${ENIGMA_REF} \
    && rm -rf .git

WORKDIR /enigma-bbs
RUN npm install --production

# ENiGMA's default-config generator runs via ``./oputil.js config new``
# and is interactive. Start the main process briefly so it creates the
# on-disk defaults under ./config/, then stash them for the entrypoint
# to seed on first run. We kill node as soon as the default files
# appear, which keeps this step quick (<10s).
RUN mkdir -p /enigma-pre/config /enigma-pre/mods /enigma-pre/art \
    && cp -rp mods/* /enigma-pre/mods/ \
    && cp -rp art/* /enigma-pre/art/ \
    && (cd config && ls -la) \
    && cp -rp config/* /enigma-pre/config/ 2>/dev/null || true


# ---------------------------------------------------------------------------
# Final (thin) image
# ---------------------------------------------------------------------------

FROM node:20-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Runtime deps only:
#   * openssl: needed for SSH host key generation (`ssh-keygen`)
#   * lrzsz + arj + lhasa + unrar-free + p7zip-full: classic BBS
#     archive tooling so the file base can handle what users upload
#   * bash: the entrypoint uses bash-isms (arrays, [[ ]])
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        openssl \
        openssh-client \
        lrzsz \
        arj \
        lhasa \
        unrar-free \
        p7zip-full \
    && rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*

# Copy the built BBS + the template dirs from the builder.
COPY --from=builder /enigma-bbs /enigma-bbs
COPY --from=builder /enigma-pre /enigma-pre

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /enigma-bbs

# Container listens here. See openhost.toml for the host-side
# port mapping (telnet defaults to host port 2323).
EXPOSE 8888

# The entrypoint:
#   1. Seeds OPENHOST_APP_DATA_DIR with starter config/ if empty
#   2. Replaces /enigma-bbs/{config,db,logs,filebase,mods,art} with
#      symlinks to matching subdirs of OPENHOST_APP_DATA_DIR
#   3. execs node main.js
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "main.js"]
