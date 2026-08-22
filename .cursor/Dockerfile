FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        git \
        unzip \
        xz-utils \
        zip \
        libglu1-mesa \
        clang \
        cmake \
        ninja-build \
        pkg-config \
        libgtk-3-dev \
        liblzma-dev \
        libstdc++-12-dev \
        libstdc++-14-dev \
        g++ \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

ENV FLUTTER_HOME=/opt/flutter
ENV FLUTTER_GIT_URL=https://github.com/flutter/flutter.git
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"

RUN curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.1-stable.tar.xz -o /tmp/flutter.tar.xz \
    && mkdir -p /opt \
    && tar -xf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && flutter config --no-analytics \
    && flutter precache --linux --web
