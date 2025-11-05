#!/bin/bash
# -------------------------------------------------------
# HealthMon - Simple Server Health Monitoring Script
# -------------------------------------------------------

CONFIG_FILE="/etc/healthmon.conf"
LOG_FILE="/var/log/healthmon.log"

SILENT=false
SEND_EMAIL=false
SEND_SLACK=false

ENV_PATH="/opt/healthmon/.env"

if [ -f "$ENV_PATH" ]; then
  export $(grep -v '^#' "$ENV_PATH" | xargs)
else
  echo "Warning: .env file not found at $ENV_PATH"
fi

# -------------------------------------------------------
# 1. Load configuration file
# -------------------------------------------------------
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  # Default thresholds (if not defined)
  CPU=80
  RAM=70
  DISK=85
fi


# -------------------------------------------------------
# 2. Parse command-line arguments
# -------------------------------------------------------
for arg in "$@"; do
  case $arg in
    --silent) 
      SILENT=true 
      shift;; # skip to the next argument  
    --email) 
      SEND_EMAIL=true  
      shift;;
    --slack) 
      SEND_SLACK=true 
      shift;;
    # Example: --threshold CPU=85
    --threshold*)
      shift           # to skip --threshold arg and take the value after
      METRIC=$(echo "$1" | cut -d '=' -f1)
      VALUE=$(echo "$1" | cut -d '=' -f2)
      eval "${METRIC}=$VALUE"           # CPU=85
      ;;
  esac
done

# -------------------------------------------------------
# 3. System Usage Functions
# -------------------------------------------------------
cpu_usage() {
  mpstat | awk '$13 ~ /[0-9.]+/ { printf "%.2f", 100 - $13 }'  
}

ram_usage() {
  free -h | grep 'Mem' | awk '{printf("%.2f", $3/$2*100)}'
}

disk_usage() {
  df / | awk 'NR==2 {print $5 }' | sed 's/%//' 
}

# -------------------------------------------------------
# 4. Threshold Check Function
# -------------------------------------------------------
check_threshold() {
  local metric=$1
  local value=$2
  local threshold=$3

  if (( $(echo "$value > $threshold" | bc -l) )); then
    log_json "$metric" "$value" "$threshold" "ALERT"
    send_alert "$metric" "$value" "$threshold"
  else
    log_json "$metric" "$value" "$threshold" "OK"
    if [ "$SILENT" = false ]; then
      echo "$metric usage OK: $value%"
    fi
  fi
}

# -------------------------------------------------------
# 4. Logging Function
# -------------------------------------------------------
log_json() {
  local metric=$1
  local value=$2
  local threshold=$3
  local status=$4
  local timestamp
  timestamp=$(date -u +%FT%TZ)

  echo "{\"timestamp\": \"$timestamp\", \"metric\": \"$metric\", \"value\": $value, \"threshold\": $threshold, \"status\": \"$status\"}" >> "$LOG_FILE"
}

# -------------------------------------------------------
# 5. Alert Sending Function
# -------------------------------------------------------
send_alert() {
  local metric=$1
  local value=$2
  local threshold=$3
  local message="ALERT: $metric usage is ${value}% (threshold ${threshold}%)"

  # Email alert
  if [ "$SEND_EMAIL" = true ]; then
    echo "$message" | mail -s "HealthMon Alert: $metric" salma    # current user but we can change it to mail 
  fi

  # Slack alert 
  if [ "$SEND_SLACK" = true ]; then
    curl -s -X POST -H 'Content-type: application/json' \
      --data "{\"text\": \"$message\"}" \
      "$SLACK_WEBHOOK_URL" > /dev/null
  fi

  # Console alert
  if [ "$SILENT" = false ]; then
    echo "$message"
  fi
}


# -------------------------------------------------------
# 7. Run the Checks
# -------------------------------------------------------
CPU_NOW=$(cpu_usage)
RAM_NOW=$(ram_usage)
DISK_NOW=$(disk_usage)

check_threshold "CPU" "$CPU_NOW" "$CPU"
check_threshold "RAM" "$RAM_NOW" "$RAM"
check_threshold "DISK" "$DISK_NOW" "$DISK"