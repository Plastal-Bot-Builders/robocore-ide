# RoboCore compile server: arduino-cli + esp32 core + RoboCore library + a small Node server.
# Build from the repo root (it copies firmware/RoboCore):
#   docker build -f server/Dockerfile -t robocore-compile .
#   docker run --rm -p 8080:8080 robocore-compile
FROM node:22-bookworm-slim

ARG ARDUINO_CLI_VERSION=1.5.1
ARG ESP32_CORE_VERSION=3.3.12
ARG AVR_CORE_VERSION=1.8.6

# python3 runs the esp32 core's partition tool during builds.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl python3 \
 && rm -rf /var/lib/apt/lists/*

# arduino-cli, checked against the published checksum.
RUN set -eux; \
    f="arduino-cli_${ARDUINO_CLI_VERSION}_Linux_64bit.tar.gz"; \
    cd /tmp; \
    curl -fsSLO "https://downloads.arduino.cc/arduino-cli/${f}"; \
    curl -fsSL "https://downloads.arduino.cc/arduino-cli/${ARDUINO_CLI_VERSION}-checksums.txt" -o sums.txt; \
    grep " ${f}\$" sums.txt | sha256sum -c -; \
    tar -xzf "${f}" -C /usr/local/bin arduino-cli; \
    rm -f "${f}" sums.txt; \
    arduino-cli version

# Builds run as an ordinary user with nothing secret in its home folder.
RUN useradd --create-home --uid 10001 builder
USER builder
ENV HOME=/home/builder
WORKDIR /home/builder

RUN set -eux; \
    arduino-cli config init; \
    arduino-cli config set board_manager.additional_urls https://espressif.github.io/arduino-esp32/package_esp32_index.json; \
    arduino-cli core update-index; \
    arduino-cli core install "esp32:esp32@${ESP32_CORE_VERSION}"; \
    arduino-cli core install "arduino:avr@${AVR_CORE_VERSION}"; \
    arduino-cli lib update-index; \
    arduino-cli lib install "ESP32Servo@3.2.1" "Adafruit NeoPixel@1.12.3" "NewPing@1.9.7" "LiquidCrystal I2C@1.1.2"; \
    arduino-cli core list; arduino-cli lib list

COPY --chown=builder:builder firmware/RoboCore /home/builder/robocore/firmware/RoboCore
COPY --chown=builder:builder server /home/builder/robocore/server
# The Anthropic SDK, for Cog (the only package; versions are pinned in package-lock.json).
RUN cd /home/builder/robocore/server && npm ci --omit=dev --no-audit --no-fund

# Warm the build cache so the first real compile is quick, and prove the toolchain works.
RUN set -eux; \
    cd /home/builder/robocore; \
    arduino-cli compile --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=enabled,CPUFreq=240" \
      --library firmware/RoboCore --build-path /tmp/warm firmware/RoboCore/examples/Blink; \
    rm -rf /tmp/warm

WORKDIR /home/builder/robocore/server
ENV PORT=8080 \
    NODE_ENV=production \
    ROBOCORE_LIBRARY=/home/builder/robocore/firmware/RoboCore
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "src/server.js"]
