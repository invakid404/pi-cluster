#!/usr/bin/env bash
set -e

sudo apt update
sudo apt install -y \
  curl \
  jq \
  libnss3 \
  libatk1.0-0 \
  libatk-bridge2.0-0 \
  libcups2 \
  libdrm2 \
  libxkbcommon0 \
  libxcomposite1 \
  libxdamage1 \
  libxfixes3 \
  libxrandr2 \
  libgbm1 \
  libpango-1.0-0 \
  libcairo2 \
  libasound2 \
  libatspi2.0-0 \
  libwayland-client0 \
  fonts-liberation \
  xvfb

# Playwright will download its own bundled Chromium at install time in the
# consuming project, but the system libraries above are required for it to
# launch. If the project uses `npx playwright install --with-deps chromium`,
# that would also pull these, but pre-installing them in the image avoids
# repeated downloads and sudo requirements at runtime.
