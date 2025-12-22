#!/bin/bash

# Configuration
APP_DIR="/mnt/mitradisk/app/prod5"
STACK_NAME="prod5"
HEALTH_URL="https://127.0.0.1:8080/version"
CHECK_INTERVAL=30 # Seconds between checks
MAX_FAILURES=3
RESTART_WAIT_TIME=20 # Seconds to wait between stack rm and deploy
WAITING_AFTER_RESTART=180 # Seconds to wait after restart sequence completly

MAINTENANCE_WINDOW_START="0655"
MAINTENANCE_WINDOW_END="0715"
WAIT_AFTER_MAINTENANCE_WINDOW=60 # Seconds to wait after maintenance window

# Log file
LOG_FILE="/var/log/mitra_monitor.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Ensure log file exists and is writable
touch "$LOG_FILE" 2>/dev/null || { echo "Cannot write to $LOG_FILE. Running without log file."; LOG_FILE="/dev/null"; }

log_message "Starting Mitra Application Monitor..."
log_message "Monitoring URL: $HEALTH_URL on each $CHECK_INTERVAL seconds"

FAILURE_COUNT=0

while true; do
    # Maintenance window check: 06:55 to 07:15
    # During this period, we skip health checks to allow for scheduled maintenance
    # Force base 10 arithmetic to avoid octal interpretation of 08 and 09
    current_time=$(date +%H%M)
    if [[ "1$current_time" -ge "1$MAINTENANCE_WINDOW_START" && "1$current_time" -le "1$MAINTENANCE_WINDOW_END" ]]; then
        log_message "Maintenance window ($MAINTENANCE_WINDOW_START-$MAINTENANCE_WINDOW_END). Skipping health check."
        sleep "$WAIT_AFTER_MAINTENANCE_WINDOW"
        continue
    fi

    # Check health URL
    # -s: Silent mode
    # -f: Fail silently (no output) on HTTP errors (4xx, 5xx)
    # --connect-timeout: Timeout for connection
    if curl -k -s -f --connect-timeout 10 "$HEALTH_URL" > /dev/null; then
        if [ $FAILURE_COUNT -gt 0 ]; then
            log_message "Health check recovered. Previous failures: $FAILURE_COUNT"
        fi
        FAILURE_COUNT=0
    else
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        log_message "Health check failed! Attempt $FAILURE_COUNT of $MAX_FAILURES"
        
        if [ $FAILURE_COUNT -ge $MAX_FAILURES ]; then
            log_message "Max failures reached. Initiating restart sequence..."
            
            # 1. Run thread dump script
            if [ -f "$APP_DIR/gerar_thread_dump.sh" ]; then
                log_message "Generating thread dump..."
                # Assuming the script needs to be run from its directory or handles paths correctly.
                # The user command was: sudo bash gerar_thread_dump.sh guacamole4436
                # We are running as root (via systemd or sudo), so sudo inside might be redundant but harmless if NOPASSWD.
                # Adjusting to run bash directly.
                (cd "$APP_DIR" && bash gerar_thread_dump.sh "$STACK_NAME") >> "$LOG_FILE" 2>&1
            else
                log_message "Warning: Thread dump script not found at $APP_DIR/gerar_thread_dump.sh"
            fi
            
            # 2. Remove docker stack
            log_message "Removing docker stack: $STACK_NAME"
            docker stack rm "$STACK_NAME" >> "$LOG_FILE" 2>&1
            
            # 3. Wait
            log_message "Waiting ${RESTART_WAIT_TIME} seconds..."
            sleep "$RESTART_WAIT_TIME"
            
            # 4. Deploy docker stack
            COMPOSE_FILE="$APP_DIR/docker-compose.yaml"
            if [ -f "$COMPOSE_FILE" ]; then
                log_message "Deploying docker stack from $COMPOSE_FILE"
                docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME" >> "$LOG_FILE" 2>&1
            else
                log_message "CRITICAL ERROR: Docker compose file not found at $COMPOSE_FILE"
            fi

            # 5. Wait for restart sequence to complete
            sleep "$WAITING_AFTER_RESTART"
            
            # Reset counter after restart attempt to allow time for startup
            # We might want to give it a grace period, but the loop will just count up again if it fails immediately.
            FAILURE_COUNT=0
            log_message "Restart sequence completed."
        fi
    fi
    
    sleep "$CHECK_INTERVAL"
done

