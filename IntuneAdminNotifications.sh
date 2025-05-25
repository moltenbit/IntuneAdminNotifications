#!/bin/bash

TENANT_ID="XXX"
CLIENT_ID="YYY"
CLIENT_SECRET="ZZZ"

BASE_DIR="/opt/intune"
KNOWN_DEVICES="$BASE_DIR/known_devices.txt"
TMP_DEVICES="$BASE_DIR/current_devices.tmp"
LOG="$BASE_DIR/intune.log"
ERROR_FILE="$BASE_DIR/last_error_response.json"

EMAIL_TO="XXX"
EMAIL_FROM="YYY"
SUBJECT="New Intune Devices Detected"

TOKEN_RESPONSE=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$CLIENT_ID&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default&client_secret=$CLIENT_SECRET&grant_type=client_credentials")

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "$(date): Failed to obtain access token" >> "$LOG"
  exit 1
fi

DEVICE_DATA=$(curl -s -X GET "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices" \
  -H "Authorization: Bearer $TOKEN")

echo "$DEVICE_DATA" | jq '.value' >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "$(date): Graph API returned unexpected response, saving to $ERROR_FILE" >> "$LOG"
  echo "$DEVICE_DATA" > "$ERROR_FILE"
  exit 1
fi

echo "$DEVICE_DATA" | jq -r '.value[] | "\(.deviceName) | \(.userPrincipalName) | \(.id) | \(.enrolledDateTime)"' | sort > "$TMP_DEVICES"

if [[ -f "$KNOWN_DEVICES" ]]; then
  NEW_DEVICES=$(comm -13 "$KNOWN_DEVICES" "$TMP_DEVICES")
else
  NEW_DEVICES=$(cat "$TMP_DEVICES")
fi

echo "$(date): Script run. New devices: $(echo "$NEW_DEVICES" | grep -c .)" >> "$LOG"

if [[ -n "$NEW_DEVICES" ]]; then
  {
    echo "Subject: $SUBJECT"
    echo "From: $EMAIL_FROM"
    echo "To: $EMAIL_TO"
    echo
    echo "New devices enrolled in Intune:"
    echo
    echo "$NEW_DEVICES"
  } | msmtp "$EMAIL_TO"
fi

cp "$TMP_DEVICES" "$KNOWN_DEVICES"
rm -f "$TMP_DEVICES"
