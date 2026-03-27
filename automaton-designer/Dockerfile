# ── Stage 1: Build ────────────────────────────────────────────────────
FROM haskell:9.8-slim AS builder

WORKDIR /build

# Copy dependency files first for layer caching
COPY automaton-designer.cabal cabal.project ./
RUN cabal update && cabal build --only-dependencies --enable-tests

# Copy source and build
COPY . .
RUN cabal build exe:automaton-designer \
    && cp $(cabal list-bin automaton-designer) /build/server

# ── Stage 2: Runtime ──────────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgmp10 locales \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

WORKDIR /app

COPY --from=builder /build/server ./automaton-designer
COPY --from=builder /build/static ./static

ENV PORT=8023
EXPOSE 8023

ENTRYPOINT ["./automaton-designer"]
