# Unicron Business Edition

This folder is the complete connected installation. Docker Compose pulls the
supported public Business images; no LogForge registry login is required.

```bash
docker compose up -d
```

Open `https://localhost`, accept the locally owned certificate only after you
trust `data/pki/trust/root_ca.crt`, and set the first `owner` password. The
default deployment stores its retained data in `./data`.

To use another domain, port, data directory, or owner name, copy
`.env.example` to `.env` and edit it before the first startup. Image versions,
component compatibility, signing trust, and generated secrets are not operator
choices.

Use `docker compose ps`, `docker compose logs`, and `docker compose down` for
normal operation. `down` preserves data; `docker compose down -v` does not
remove the bind-mounted `data` directory.

After installation, use **Settings > Updates & releases** in Central. The
product verifies the signed exact successor and coordinates Central, Echo,
Ghost, and central-updater as one supported release. Do not use
`docker compose pull` as a product-update command; ordinary restarts remain
`docker compose up -d`.

This is proprietary LogForge software. See `LICENSE` for the applicable terms.
