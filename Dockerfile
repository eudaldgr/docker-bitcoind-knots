# Global arguments
ARG APP_UID=1000
ARG APP_GID=1000

FROM ghcr.io/eudaldgr/scratchless AS scratchless

# Build stage
FROM docker.io/alpine AS build
ARG APP_VERSION \
  APP_ROOT \
  TARGETARCH \
  TARGETVARIANT

ARG KEYS

RUN set -ex; \
  apk --no-cache --update add \
  build-base \
  cmake \
  linux-headers \
  pkgconf \
  python3 \
  libevent-dev \
  boost-dev \
  zeromq-dev \
  gnupg \
  wget \
  tar \
  jq \
  curl;

RUN set -ex; \
  wget https://bitcoinknots.org/files/${APP_VERSION%%.*}.x/${APP_VERSION}/bitcoin-${APP_VERSION}.tar.gz \
  https://bitcoinknots.org/files/${APP_VERSION%%.*}.x/${APP_VERSION}/SHA256SUMS.asc \
  https://bitcoinknots.org/files/${APP_VERSION%%.*}.x/${APP_VERSION}/SHA256SUMS;

RUN set -ex; \
  curl -s "https://api.github.com/repos/bitcoinknots/guix.sigs/contents/builder-keys" | jq -r '.[].download_url' | while read url; do curl -s "$url" | gpg --import; done; \
  gpg --verify SHA256SUMS.asc SHA256SUMS;

RUN set -ex; \
  [ -f SHA256SUMS ] && cp SHA256SUMS sha256sums || cp SHA256SUMS.asc sha256sums;

RUN set -ex; \
  grep "bitcoin-${APP_VERSION}.tar.gz" sha256sums | sha256sum -c;

RUN set -ex; \
  tar xzf bitcoin-${APP_VERSION}.tar.gz;

ENV BITCOIN_GENBUILD_NO_GIT=1
RUN set -ex; \
  cd bitcoin-${APP_VERSION}; \
  cmake -S . -B build \
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
  -DINSTALL_MAN=OFF;

RUN set -ex; \
  cd bitcoin-${APP_VERSION}; \
  cmake --build build --target bitcoind -j "$(nproc)";

RUN set -ex; \
  cd bitcoin-${APP_VERSION}; \
  strip build/bin/bitcoind;

COPY --from=scratchless / ${APP_ROOT}/

RUN set -ex; \
  mkdir -p \
  ${APP_ROOT}/bin \
  ${APP_ROOT}/data \
  ${APP_ROOT}/etc \
  ${APP_ROOT}/lib;

RUN set -ex; \
  cd bitcoin-${APP_VERSION}; \
  cp build/bin/bitcoind ${APP_ROOT}/bin/;

RUN set -ex; \
  ldd ${APP_ROOT}/bin/bitcoind | awk '{if (match($3,"/")) print $3}' | xargs -I '{}' cp -v '{}' ${APP_ROOT}/lib/ || true;

RUN set -ex; \
  cp /lib/ld-musl-*.so.1 ${APP_ROOT}/lib/;

# Final scratch image
FROM scratch

ARG TARGETPLATFORM \
  TARGETOS \
  TARGETARCH \
  TARGETVARIANT \
  APP_IMAGE \
  APP_NAME \
  APP_VERSION \
  APP_ROOT \
  APP_UID \
  APP_GID \
  APP_NO_CACHE

ENV APP_IMAGE=${APP_IMAGE} \
  APP_NAME=${APP_NAME} \
  APP_VERSION=${APP_VERSION} \
  APP_ROOT=${APP_ROOT}

COPY --from=build ${APP_ROOT}/ /

ENV HOME=/data
VOLUME /data/.bitcoin

# 8332  Mainnet RPC
# 8333  Mainnet P2P
# 18332 Testnet3 RPC
# 18333 Testnet3 P2P
# 48332 Testnet4 P2P
# 48333 Testnet4 RPC
# 38332 Signet RPC
# 38333 Signet P2P
# 18443 Regtest RPC
# 18444 Regtest P2P
EXPOSE 8332 8333 18332 18333 48332 48333 38332 38333 18443 18444

USER ${APP_UID}:${APP_GID} 
ENTRYPOINT ["/bin/bitcoind"]