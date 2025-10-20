#!/bin/bash

#nano /opt/zimbra/scripts/cleanup.sh
#chmod +x /opt/zimbra/scripts/cleanup.sh
#su - zimbra
#/opt/zimbra/scripts/cleanup.sh

# --- ⚠️ SCRIPT HARDENING ---
set -euo pipefail
# --------------------------

# --- ⚠️ WARNING ---
# This script permanently deletes mail. Always ensure you have a backup.

# --- Security Check: Ensure script is run as the 'zimbra' user ---
REQUIRED_USER="zimbra"
CURRENT_USER=$(whoami)

if [ "$CURRENT_USER" != "$REQUIRED_USER" ]; then
    echo "---------------------------------------------------------"
    echo "FATAL ERROR: This script must be run as the '$REQUIRED_USER' user."
    echo "Current user is '$CURRENT_USER'."
    echo "Please switch user with: su - $REQUIRED_USER"
    echo "---------------------------------------------------------"
    exit 1
fi
# ------------------------------------------------------------------

# --- Configuration ---
FOLDERS=(
  "/Inbox"
  "/Sent"
  "/Drafts"
  "/Junk"
  "/Trash"
)

BATCH_SIZE=1000

# Path for temporary files
TMP_DIR="/tmp/zimbra_cleanup_$$"

# Setup temporary directory and cleanup on exit
mkdir -p "$TMP_DIR"
trap "rm -rf '$TMP_DIR'" EXIT

# --- Interactive Prompts ---

# 1. Get the age for deletion
echo "---------------------------------------------------------"
echo "Zimbra Mail Cleanup Utility (Running as $CURRENT_USER)"
echo "---------------------------------------------------------"
echo "Enter the minimum age (in days) of emails to KEEP."
read -p "Mail OLDER than this number of days will be deleted (e.g., 365): " AGE_DAYS

# Validate input
if ! [[ "$AGE_DAYS" =~ ^[0-9]+$ ]] || [ "$AGE_DAYS" -eq 0 ]; then
    echo "ERROR: Invalid age entered. Must be a number greater than 0."
    exit 1
fi

AGE="${AGE_DAYS}d"

echo
echo "SUMMARY OF ACTION:"
echo "---------------------------------------------------------"
echo "Mail older than $AGE_DAYS days will be PERMANENTLY DELETED."
echo "This action will affect ALL user accounts in the following folders: ${FOLDERS[*]}"
echo "---------------------------------------------------------"

# 2. Confirmation Prompt
read -r -p "Are you ABSOLUTELY sure you want to proceed? Type 'YES' to confirm: " CONFIRMATION

if [ "$CONFIRMATION" != "YES" ]; then
    echo "Operation cancelled by user."
    exit 0
fi

# --- Execution ---

echo
echo "Starting cleanup process..."
echo "---------------------------------------------------------"

# Get list of all accounts
ACCOUNTS=$(zmprov -l gaa)

# Convert list to array and get total count for progress tracking
ACCOUNT_ARRAY=($ACCOUNTS)
TOTAL_ACCOUNTS=${#ACCOUNT_ARRAY[@]}
CURRENT_COUNT=0

# Iterate over each account
for ACCOUNT in "${ACCOUNT_ARRAY[@]}"; do
    CURRENT_COUNT=$((CURRENT_COUNT + 1))
    # Calculate percentage (using a simple integer division approximation for progress)
    PERCENT_COMPLETE=$(( (CURRENT_COUNT * 100) / TOTAL_ACCOUNTS ))
    
    # Progress Indicator
    echo -e "\n=== Processing Account $CURRENT_COUNT of $TOTAL_ACCOUNTS ($PERCENT_COMPLETE%): $ACCOUNT ==="
    
    # Iterate over each folder to be cleaned
    for FOLDER in "${FOLDERS[@]}"; do
        TEMP_FILE="$TMP_DIR/$ACCOUNT.$(basename $FOLDER).txt"
        
        echo "  - Searching for old messages in folder: $FOLDER"
        
        # Loop to handle large numbers of items by running deletion in batches
        while true; do
            # Search for messages older than the specified age in the folder
            zmmailbox -z -m "$ACCOUNT" s -l $BATCH_SIZE "in:$FOLDER before:-$AGE" | \
            
            # Use awk to filter out headers (FNR>3) and generate delete commands
            awk 'FNR>3 {
                if ($2 ~ /^[0-9]+,|-/) {
                    print "deleteConversation " $2
                } else if ($2 ~ /^[0-9]+$/) {
                    print "deleteMessage " $2
                }
            }' > "$TEMP_FILE"

            COUNT=$(wc -l < "$TEMP_FILE")

            if [ "$COUNT" -eq 0 ]; then
                echo "    - No old items found in $FOLDER. Moving on."
                break
            fi

            echo "    - Found $COUNT items. Deleting batch of up to $BATCH_SIZE..."
            
            # Execute the batch deletion commands using file input
            zmmailbox -z -m "$ACCOUNT" < "$TEMP_FILE"
            
            echo "    - Deletion batch complete."
            
            # If the count is less than the batch size, we're done with this folder.
            if [ "$COUNT" -lt "$BATCH_SIZE" ]; then
                break
            fi
            
            # Pause briefly to prevent overwhelming the server
            sleep 5
        done
        
    done # End of folder loop
    echo "--- Folders for $ACCOUNT processed. ---"
done # End of account loop

echo "---------------------------------------------------------"
echo "Zimbra mail cleanup script finished. ($TOTAL_ACCOUNTS accounts processed)"
