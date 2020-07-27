FROM ubuntu:16.04 as BASE

# Install dependenciesj
RUN apt-get update && \
    apt-get install -y \
      pkg-config \
      libssl-dev \
      libgmp3-dev \
      curl \
      build-essential \
      libsqlite3-dev \
      cmake \
      git \
      python3.5 \
      python3-pip \
      python-setuptools \
      apt-transport-https \
      ca-certificates \
      debhelper \
      wget \
      devscripts \
      libncursesw5-dev \
      libzmq3-dev \
      zip \
      unzip \
      jq

RUN pip3 install -U \
	pip \
	setuptools \
	virtualenv \
	twine \
	plumbum \
	deb-pkg-tools

# Install libsodium
RUN cd /tmp && \
   curl https://download.libsodium.org/libsodium/releases/libsodium-1.0.18.tar.gz | tar -xz && \
    cd /tmp/libsodium-1.0.18 && \
    ./configure --disable-shared && \
    make && \
    make install && \
    rm -rf /tmp/libsodium-1.0.18

# Create new user
RUN useradd -ms /bin/bash -u 1000 indy
USER indy

# Install Rust toolchain
ARG RUST_VER
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain ${RUST_VER}
ENV PATH /home/indy/.cargo/bin:$PATH

# Clone indy-sdk
ARG INDYSDK_REVISION
ARG INDYSDK_REPO
WORKDIR /home/indy
RUN git clone "${INDYSDK_REPO}" "./indy-sdk"
RUN cd "/home/indy/indy-sdk" && git checkout "${INDYSDK_REVISION}"

# Build indy binaries and move to system library
# TODO: It should be possible to run a single command as a user
RUN cargo build --release --manifest-path=/home/indy/indy-sdk/libindy/Cargo.toml
USER root
RUN mv /home/indy/indy-sdk/libindy/target/release/*.so /usr/lib
USER indy 
RUN cargo build --release --manifest-path=/home/indy/indy-sdk/libnullpay/Cargo.toml
USER root
RUN mv /home/indy/indy-sdk/libnullpay/target/release/*.so /usr/lib

# Build libvcx
WORKDIR /home/indy
USER indy
COPY --chown=indy  ./ ./
RUN cargo build --release --manifest-path=/home/indy/libvcx/Cargo.toml

# Move the binary to system library
USER root
RUN mv /home/indy/libvcx/target/release/*.so /usr/lib


# Create a new build stage and copy outputs from BASE
FROM ubuntu:16.04

RUN apt-get update && \
    apt-get install -y \
      libssl-dev \
      apt-transport-https \
      ca-certificates \
      curl \
      build-essential

RUN useradd -ms /bin/bash -u 1000 indy

WORKDIR /home/indy

COPY --from=BASE /var/lib/dpkg/info /var/lib/dpkg/info
COPY --from=BASE /usr/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu
COPY --from=BASE /usr/local /usr/local

COPY --from=BASE --chown=indy /usr/lib/libindy.so /usr/lib/libindy.so
COPY --from=BASE --chown=indy /usr/lib/libvcx.so /usr/lib/libvcx.so
COPY --from=BASE --chown=indy /usr/lib/libnullpay.so /usr/lib/libnullpay.so

COPY --from=BASE --chown=indy /home/indy/libvcx ./libvcx
COPY --from=BASE --chown=indy /home/indy/wrappers/node ./wrappers/node

# Install node
ARG NODE_VER
RUN curl -sL https://deb.nodesource.com/setup_${NODE_VER} | bash -
RUN apt-get install -y nodejs

RUN chown -R indy . 

USER indy

# TODO: Just copy the binary and add to path
ARG RUST_VER
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain ${RUST_VER}
ENV PATH /home/indy/.cargo/bin:$PATH

LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.name="libvcx"
LABEL org.label-schema.version="${INDYSDK_REVISION}"
