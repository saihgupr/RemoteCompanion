#!/bin/bash

# Configuration
PIPE="/var/mobile/rc_pipe"
SHORTCUTS_BIN_PATH="/var/jb/usr/bin/springcuts"
LOG_FILE="/var/mobile/rc_server.log"

# Create the pipe if it doesn't exist
[ -p "$PIPE" ] || mkfifo "$PIPE"
chmod 666 "$PIPE"

echo "[$(date)] RC Pipe Server (Fire-and-Forget) started. Listening on $PIPE" | tee -a "$LOG_FILE"

while true; do
    if read -r LINE < "$PIPE"; then
        if [ -n "$LINE" ]; then
            if [[ "$LINE" == shortcut* ]]; then
                # New style: Tweak forwards "shortcut -r 'Name' ..."
                # Strip "shortcut " and pass the rest to springcuts directly
                ARGS=${LINE#shortcut }
                echo "$(date) | Executing: $SHORTCUTS_BIN_PATH $ARGS" >> "$LOG_FILE"
                # We need to use eval to handle quotes properly in $ARGS
                eval "\"$SHORTCUTS_BIN_PATH\" $ARGS" >/dev/null 2>&1 &
            else
                # Old style: Name|Input
                SHORTCUT=$(echo "$LINE" | cut -d'|' -f1)
                INPUT=$(echo "$LINE" | cut -d'|' -f2)

                if [ -n "$INPUT" ] && [ "$INPUT" != "$SHORTCUT" ]; then
                    "$SHORTCUTS_BIN_PATH" -r "$SHORTCUT" -p "$INPUT" >/dev/null 2>&1 &
                else
                    "$SHORTCUTS_BIN_PATH" -r "$SHORTCUT" >/dev/null 2>&1 &
                fi
            fi
        fi
    fi
done
