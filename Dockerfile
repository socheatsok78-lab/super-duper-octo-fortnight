# Nix builder
FROM nixos/nix:latest AS builder

COPY <<EOF /etc/nix/nix.conf
filter-syscalls = false
experimental-features = nix-command flakes
EOF

# Mount source and setup working dir.
# Build our Nix environment
COPY . /tmp/build
WORKDIR /tmp/build
RUN nix build -o /tmp/result
# RUN --mount=type=bind,target=/tmp/build nix build -o /tmp/result

# Copy the Nix store closure into a directory. The Nix store closure is the
# entire set of Nix store values that we need for our build.
RUN mkdir /tmp/nix-store-closure
RUN cp -R $(nix-store -qR /tmp/result) /tmp/nix-store-closure

# Final image is based on scratch. We copy a bunch of Nix dependencies
# but they're fully self-contained so we don't need Nix anymore.
FROM scratch

WORKDIR /app

# Copy /nix/store
COPY --from=builder /tmp/nix-store-closure /nix/store
COPY --from=builder /tmp/result /result
CMD ["/result/bin/nbcp-ncs-frontend-server"]
