# The Color Claim online server: Godot with no screen, running godot/server/run.gd.
# Hosts like Render and Fly.io build this file straight from the repository (see SERVER.md).
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && unzip -q "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && mv "Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && rm "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"

WORKDIR /app
COPY godot/ /app/godot/
# Import once while building, so the server starts quickly
RUN godot --headless --path /app/godot --import || true

# The host tells the server which port to use (Render and Fly.io set PORT)
ENV PORT=8080
EXPOSE 8080
CMD ["godot", "--headless", "--path", "/app/godot", "-s", "server/run.gd"]
