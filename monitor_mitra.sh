#!/bin/bash

# Configuration
APP_DIR="/home/mitra/app/guacamole"
STACK_NAME="guacamole4436"
HEALTH_URL="https://localhost:8080/version"
CHECK_INTERVAL=60 # Seconds between checks
MAX_FAILURES=3
RESTART_WAIT_TIME=20 # Seconds to wait between stack rm and deploy

# Log file
LOG_FILE="/var/log/mitra_monitor.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Ensure log file exists and is writable
touch "$LOG_FILE" 2>/dev/null || { echo "Cannot write to $LOG_FILE. Running without log file."; LOG_FILE="/dev/null"; }

log_message "Starting Mitra Application Monitor..."
log_message "Monitoring URL: $HEALTH_URL"

FAILURE_COUNT=0

while true; do
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
            
            # 2. Update docker images
            log_message "Pulling updated docker images..."
            if [ -f "$APP_DIR/docker-compose.yaml" ]; then
                (cd "$APP_DIR" && docker-compose pull) >> "$LOG_FILE" 2>&1
            else
                 log_message "Warning: docker-compose.yaml not found at $APP_DIR"
            fi
            
            # 3. Remove docker stack
            log_message "Removing docker stack: $STACK_NAME"
            docker stack rm "$STACK_NAME" >> "$LOG_FILE" 2>&1
            
            # 4. Wait
            log_message "Waiting ${RESTART_WAIT_TIME} seconds..."
            sleep "$RESTART_WAIT_TIME"
            
            # 5. Deploy docker stack
            COMPOSE_FILE="$APP_DIR/docker-compose.yaml"
            if [ -f "$COMPOSE_FILE" ]; then
                log_message "Deploying docker stack from $COMPOSE_FILE"
                docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME" >> "$LOG_FILE" 2>&1
            else
                log_message "CRITICAL ERROR: Docker compose file not found at $COMPOSE_FILE"
            fi
            
            # Reset counter after restart attempt to allow time for startup
            # We might want to give it a grace period, but the loop will just count up again if it fails immediately.
            FAILURE_COUNT=0
            log_message "Restart sequence completed."
        fi
    fi
    
    sleep "$CHECK_INTERVAL"
done

