# W2.4.1-PDF part A: local LibreOffice converter for the registered OPL-W-01 DOCX.
# Base image pinned by digest; Debian packages pinned through the snapshot archive of the same date.
# The image has no entrypoint that uses the network; conversions run with --network none.
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

ARG DEBIAN_SNAPSHOT=20260918T000000Z

RUN printf 'Types: deb\nURIs: http://snapshot.debian.org/archive/debian/%s\nSuites: trixie trixie-updates\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\nCheck-Valid-Until: no\n\nTypes: deb\nURIs: http://snapshot.debian.org/archive/debian-security/%s\nSuites: trixie-security\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\nCheck-Valid-Until: no\n' \
      "$DEBIAN_SNAPSHOT" "$DEBIAN_SNAPSHOT" > /etc/apt/sources.list.d/debian.sources \
  && apt-get -o Acquire::Check-Valid-Until=false update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       libreoffice-writer-nogui fonts-crosextra-carlito poppler-utils imagemagick \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --uid 10001 --create-home --home-dir /home/converter converter

USER 10001:10001
WORKDIR /work
