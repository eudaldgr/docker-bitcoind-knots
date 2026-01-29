# Build stage
FROM docker.io/alpine:3.23.3@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659 AS builder

ARG VERSION
ARG TARGETPLATFORM
ARG KEYS

ARG APP_UID=1000
ARG APP_GID=1000

WORKDIR /build

# Set optimized compiler flags
ENV CFLAGS="-O3 -pipe -fPIE"
ENV CXXFLAGS="-O3 -pipe -fPIE"
ENV LDFLAGS="-pie -Wl,--as-needed"
ENV MAKEFLAGS="-j$(nproc)"

RUN echo "Installing build deps"
RUN apk add --no-cache --virtual .build-deps \
  build-base cmake linux-headers pkgconf python3 \
  libevent-dev boost-dev \
  zeromq-dev \
  gnupg wget tar jq curl

RUN echo "Downloading release assets"
RUN wget https://bitcoinknots.org/files/${VERSION%%.*}.x/${VERSION}/bitcoin-${VERSION}.tar.gz
RUN wget https://bitcoinknots.org/files/${VERSION%%.*}.x/${VERSION}/SHA256SUMS.asc
RUN wget https://bitcoinknots.org/files/${VERSION%%.*}.x/${VERSION}/SHA256SUMS
RUN echo "Downloaded release assets:" && ls

RUN echo "Verifying PGP signatures"
RUN curl -s "https://api.github.com/repos/bitcoinknots/guix.sigs/contents/builder-keys" | jq -r '.[].download_url' | while read url; do curl -s "$url" | gpg --import; done
RUN gpg --verify SHA256SUMS.asc SHA256SUMS
RUN echo "PGP signature verification passed"

RUN echo "Verifying checksums"
RUN [ -f SHA256SUMS ] && cp SHA256SUMS /sha256sums || cp SHA256SUMS.asc /sha256sums
RUN grep "bitcoin-${VERSION}.tar.gz" /sha256sums | sha256sum -c
RUN echo "Checksums verified ok"

RUN echo "Extracting release assets"
RUN tar xzf bitcoin-${VERSION}.tar.gz --strip-components=1

RUN echo "Build from source"
ENV BITCOIN_GENBUILD_NO_GIT=1
RUN cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DBUILD_BITCOIN_BIN=OFF \
  -DBUILD_DAEMON=ON \
  -DBUILD_GUI=OFF \
  -DBUILD_CLI=OFF \
  -DBUILD_TX=OFF \
  -DBUILD_UTIL=OFF \
  -DBUILD_UTIL_CHAINSTATE=OFF \
  -DBUILD_WALLET_TOOL=OFF \
  -DENABLE_WALLET=OFF \
  -DENABLE_IPC=OFF \
  -DENABLE_EXTERNAL_SIGNER=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_GUI_TESTS=OFF \
  -DBUILD_BENCH=OFF \
  -DBUILD_FUZZ_BINARY=OFF \
  -DBUILD_FOR_FUZZING=OFF \
  -DBUILD_KERNEL_LIB=OFF \
  -DWITH_ZMQ=ON \
  -DWITH_USDT=OFF \
  -DWITH_QRENCODE=OFF \
  -DWITH_DBUS=OFF \
  -DREDUCE_EXPORTS=ON \
  -DWERROR=OFF \
  -DWITH_CCACHE=OFF \
  -DINSTALL_MAN=OFF

RUN cmake --build build --target bitcoind -j "$(nproc)"
RUN strip build/bin/bitcoind

RUN echo "Collect all runtime dependencies"
RUN mkdir -p /runtime/lib /runtime/bin /runtime/data /runtime/etc
RUN cp build/bin/bitcoind /runtime/bin/

RUN echo "Copy all required shared libraries"
RUN ldd /runtime/bin/bitcoind | awk '{if (match($3,"/")) print $3}' | xargs -I '{}' cp -v '{}' /runtime/lib/ || true

RUN echo "Copy the dynamic linker"
RUN cp /lib/ld-musl-*.so.1 /runtime/lib/

RUN echo "Create minimal user files"
RUN echo "bitcoin:x:${APP_UID}:${APP_GID}:bitcoin:/data:/sbin/nologin" > /runtime/etc/passwd
RUN echo "bitcoin:x:${APP_GID}:" > /runtime/etc/group

RUN echo "Set ownership for data directory"
RUN chown -R ${APP_UID}:${APP_GID} /runtime/data

# Final scratch image
FROM scratch
LABEL org.opencontainers.image.authors="eudaldgr <https://eudald.gr>"

ARG APP_UID=1000
ARG APP_GID=1000

# Copy everything from runtime
COPY --from=builder /runtime/ /

ENV HOME=/data
VOLUME /data/.bitcoin

EXPOSE 8332 8333 18332 18333 18443 18444

USER ${APP_UID}:${APP_GID} 
ENTRYPOINT ["/bin/bitcoind"]
