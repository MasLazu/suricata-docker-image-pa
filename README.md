# sensor-suricata Docker image

Lightweight Docker image for running Suricata as an IDS/IPS. This repository contains the Dockerfile, Suricata template files, and environment-variable configuration used to configure the container at runtime.

## Contents

- `Dockerfile` - builds the Suricata container image.
- `templates/ids.suricata.yaml.tmpl` - Suricata configuration template for IDS mode.
- `templates/ips.suricata.yaml.tmpl` - Suricata configuration template for IPS mode.

## Build

To build the container image locally:

```bash
docker build -t sensor-suricata .
```

## Run

Create a local `.env` file (see "Configuration" below) and run the container. Examples below assume you created a `.env` file in the repo root.

Run in privileged mode (required when monitoring host network interfaces) and bind-mount `/var/run` or other paths as needed for logs or configuration:

```bash
# Example: run interactively with the .env file
docker run --rm -it --env-file .env --network host --cap-add=NET_ADMIN --cap-add=NET_RAW sensor-suricata

# Or run as a detached service and mount a directory for logs
docker run -d --env-file .env --network host --cap-add=NET_ADMIN --cap-add=NET_RAW \
  -v $(pwd)/logs:/var/log/suricata \
  --name sensor-suricata sensor-suricata
```

Note: If you are running the container in a non-host network mode, set `INTERFACE1`/`INTERFACE2` to the correct container-visible interface names.

## Configuration (Environment variables)

Create a file named `.env` in the repository root and set the variables described below. The `.env.example` file that used to ship with this repository has been removed; its documentation has been moved here.

Available environment variables:

- `SURICATA_MODE` (default: `ids`)
  - Suricata mode: `ids` for Intrusion Detection System or `ips` for Intrusion Prevention System.

- `HOME_NET` (required)
  - Home network definition (required for Suricata to work properly). Example: `192.168.1.0/24`.

- `HTTP_PORTS` (default: `80`)
  - Port(s) considered HTTP. Use comma-separated list if needed, e.g. `80,8080`.

- `SSH_PORTS` (default: `22`)
  - Port(s) considered SSH. Use comma-separated list if needed.

- `INTERFACE1`, `INTERFACE2` (required for network capture)
  - Network interfaces to monitor (must match container network setup). Example: `eth0`, `eth1` or container-specific names when not using host networking.

- `PUID`, `PGID` (optional)
  - Numeric user and group IDs used for file permissions (optional, for custom user mapping). Defaults in the image may be `1000`/`1000`.

- `ENABLE_CRON` (default: `yes`)
  - Enable cron for scheduled tasks (e.g., log rotation). Set to `yes` or `no`.

- `SURICATA_OPTIONS` (optional)
  - Additional Suricata command-line options (optional). Example: `-k none`.

- `PCAP_MODE` (default: `off`)
  - Enable a single Suricata `pcap-log` output. Supported values:
    - `off`: disable pcap logging
    - `all`: capture all packets seen by Suricata
    - `alerts`: capture packets associated with Suricata alerts
    - `tag`: capture tagged packets when rules use Suricata tagging

- `PCAP_DIR` (default: `pcap`)
  - Directory under Suricata's log directory where PCAP files are written. A relative value like `pcap` becomes `/var/log/suricata/pcap` in the container.

- `PCAP_LIMIT` (default: `100mb`)
  - Rotation size for each PCAP file.

- `PCAP_MAX_FILES` (default: `1000`)
  - Number of rotated PCAP files to retain for each output.

Example minimal `.env` file:

```ini
# Suricata mode: ids or ips
SURICATA_MODE=ids

# Home network (required)
HOME_NET=192.168.1.0/24

# Common ports
HTTP_PORTS=80
SSH_PORTS=22

# Network interfaces
INTERFACE1=eth0
INTERFACE2=eth1

# Permissions
PUID=1000
PGID=1000

# Enable cron
ENABLE_CRON=yes

# Extra options
SURICATA_OPTIONS=

# Optional Suricata pcap-log output
PCAP_MODE=off
PCAP_DIR=pcap
PCAP_LIMIT=100mb
PCAP_MAX_FILES=1000
```

## Templates

This repository contains configuration templates for Suricata in `templates/`:

- `templates/ids.suricata.yaml.tmpl` — template for IDS mode.
- `templates/ips.suricata.yaml.tmpl` — template for IPS mode.

The container entrypoint should select the appropriate template based on `SURICATA_MODE`. You can copy and modify these templates before building or mount your own configuration directory into the container.

## Troubleshooting

- If Suricata fails to bind to an interface, verify the container has the required capabilities (`NET_ADMIN`, `NET_RAW`) and that the interface name matches the host or container networking.
- Check `/var/log/suricata/` (mounted or inside container) for Suricata logs.
- If running in IPS mode, ensure any firewall or NAT rules allow the container to inline traffic or are configured correctly.

## Contributing

If you add features or change the configuration flow, update this README accordingly.

## Docker Compose example

Below is an example `docker-compose` service definition you can use (adjust image tag, networks, and interfaces to match your environment):

```yaml
services:
  suricata:
    image: mfaziz/suricata:1.1.3
    container_name: suricata-sensor
    network_mode: host
    cap_add:
      - NET_RAW
      - NET_ADMIN
      - SYS_NICE
    restart: unless-stopped
    volumes:
      - ./rules:/var/lib/suricata/rules
      - ./suricata_socket:/var/run/suricata
      # Optional snapshot/debug mount for fetched IP reputation copies
      - ./iprep-snapshots:/var/lib/suricata/iprep-snapshots
    environment:
      - SURICATA_MODE=ips
      - HOME_NET=10.10.12.0/24
      - INTERFACE1=ens19
      - INTERFACE2=ens20
      # IP Reputation polling
      - IPREP_BASE_URL=http://iprep-service:8888
      - IPREP_POLL_INTERVAL_SECONDS=300
      # Optional overrides
      # - REPUTATION_ENDPOINT=/api/v1/reputation/list
      # - CATEGORIES_ENDPOINT=/api/v1/reputation/categories
      # - REPUTATION_DEST=/var/lib/suricata/reputation.list
      # - CATEGORIES_DEST=/var/lib/suricata/reputation.categories.txt
      # Optional single Suricata pcap-log mode
      # - PCAP_MODE=all
      # - PCAP_DIR=pcap
      # - PCAP_LIMIT=100mb
      # - PCAP_MAX_FILES=1000
      # Optional IP reputation snapshots for debugging
      # - IPREP_SNAPSHOT_ENABLED=yes
      # - IPREP_SNAPSHOT_DIR=/var/lib/suricata/iprep-snapshots
      # - IPREP_SNAPSHOT_KEEP=100
```

## Optional PCAP capture

This image can optionally enable a single Suricata `pcap-log` output at runtime without editing the YAML templates by hand.

Set `PCAP_MODE` to one of:

- `all`
- `alerts`
- `tag`

Files are written under `PCAP_DIR` in a matching subdirectory:

- `${PCAP_DIR}/all/`
- `${PCAP_DIR}/alerts/`
- `${PCAP_DIR}/tag/`

Note: on the tested sensor runtime, Suricata only allowed one active `pcap-log` instance at a time, and `conditional: drop` was not accepted by this build. The practical evaluation workflow for this repository is therefore:

- enable `PCAP_MODE=all` to capture the full packet universe inside Suricata
- use EVE `action` values to distinguish `drop` from `allowed`
- correlate dropped decisions from EVE against the full PCAP when counting packets

## IP Reputation Integration

Set `IPREP_BASE_URL` to enable periodic polling of an external reputation service. The entrypoint starts a background process fetching:

- `REPUTATION_ENDPOINT` (default `/api/v1/reputation/list`)
- `CATEGORIES_ENDPOINT` (default `/api/v1/reputation/categories`)

Files are written to `/var/lib/suricata/reputation.list` and `/var/lib/suricata/reputation.categories.txt`. Suricata's configuration templates have the `reputation` section enabled and the helper script triggers a reload (via `suricatasc reload-rules` or SIGHUP) after updates.

When `IPREP_SNAPSHOT_ENABLED=yes`, each successful fetch also writes timestamped snapshot copies into `IPREP_SNAPSHOT_DIR`, plus `latest-*` copies for quick inspection. This is useful for debugging and correlating tests with the exact ip reputation state loaded on the sensor.

Environment variable summary:

| Variable | Purpose | Default |
|----------|---------|---------|
| IPREP_BASE_URL | Base URL of reputation API (enable feature) | (none) |
| IPREP_POLL_INTERVAL_SECONDS | Polling interval seconds | 300 |
| REPUTATION_ENDPOINT | Path to reputation list | /api/v1/reputation/list |
| CATEGORIES_ENDPOINT | Path to categories file | /api/v1/reputation/categories |
| REPUTATION_DEST | Destination path for list | /var/lib/suricata/reputation.list |
| CATEGORIES_DEST | Destination path for categories | /var/lib/suricata/reputation.categories.txt |
| IPREP_SNAPSHOT_ENABLED | Save timestamped copies of fetched reputation files | yes |
| IPREP_SNAPSHOT_DIR | Snapshot directory inside container | /var/lib/suricata/iprep-snapshots |
| IPREP_SNAPSHOT_KEEP | Number of timestamped snapshots to retain per file type | 100 |

### Manual Test

```bash
# One-off fetch inside container
docker exec suricata-sensor /usr/local/bin/fetch-ipreputation.sh

# Check files
docker exec suricata-sensor ls -l /var/lib/suricata/reputation.list
```
