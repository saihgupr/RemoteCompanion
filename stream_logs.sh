#!/bin/bash

# Configuration
DEVICE_IP="iphone.local"
USER="root" # Or mobile, but root usually better for reading logs
LOG_FILE="/tmp/springremote.log"

echo "📱 Connecting to $DEVICE_IP..."
echo "Starting log stream. Press Ctrl+C to stop."
echo "----------------------------------------"

# Stream the log file AND filter syslog for relevant tags
ssh -t $USER@$DEVICE_IP "tail -f $LOG_FILE"
