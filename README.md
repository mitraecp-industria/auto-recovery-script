# Mitra Application Monitoring

This directory contains scripts and configuration files to automatically monitor and restart the Mitra application `guacamole4436` stack if it becomes unresponsive.

## Contents

*   `monitor_mitra.sh`: The core logic script that performs health checks and executes the restart sequence.
*   `mitra-monitor.service`: A systemd unit file to run the monitoring script as a background service.

## Prerequisites

*   Ubuntu 22.04 LTS (or compatible).
*   Docker and Docker Swarm configured.
*   `curl` installed (`sudo apt install curl`).
*   The application files (docker-compose.yml, gerar_thread_dump.sh) located in `/home/mitra/app/guacamole`.

## Installation

Follow these steps to deploy the monitoring service:

1.  **Copy Files**
    Copy this `scripts` directory to your application folder:
    ```bash
    cp -r scripts /home/mitra/app/guacamole/
    ```

2.  **Set Permissions**
    Make the monitoring script executable:
    ```bash
    chmod +x /home/mitra/app/guacamole/scripts/monitor_mitra.sh
    ```

3.  **Install Service**
    Copy the systemd service file to the system directory:
    ```bash
    sudo cp /home/mitra/app/guacamole/scripts/mitra-monitor.service /etc/systemd/system/
    ```

4.  **Activate Service**
    Reload the systemd daemon, enable the service on boot, and start it:
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable mitra-monitor
    sudo systemctl start mitra-monitor
    ```

5.  **Verify Status**
    Check if the service is active and running:
    ```bash
    sudo systemctl status mitra-monitor
    ```

## Configuration

The `monitor_mitra.sh` script has configurable variables at the top of the file:

*   `HEALTH_URL`: The URL to check (default: `https://analytics2.mitrasheet.com:4436/version`).
*   `CHECK_INTERVAL`: Time in seconds between checks (default: `60`).
*   `MAX_FAILURES`: Number of consecutive failures before restarting (default: `3`).
*   `APP_DIR`: The directory containing the application files (default: `/home/mitra/app/guacamole`).
*   `STACK_NAME`: The Docker stack name (default: `guacamole4436`).

## Logs

The monitoring service writes logs to:
```
/var/log/mitra_monitor.log
```

You can tail the logs to see the current status:
```bash
tail -f /var/log/mitra_monitor.log
```

