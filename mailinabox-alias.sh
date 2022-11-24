#!/bin/bash

# Adds/Deletes an email alias to/from a Mail-in-a-Box instance
# Dependencies: curl
# Optional dependencies: cloak, gopass
#
# Background: https://f3.al/posts/create-email-addresses-using-bash

CONF_PATH="$HOME/.config/mailinabox_alias.conf"

# If no argument is provided, show the help screen
if [[ $# -ne 2 ]]; then
  echo "Mail-in-a-Box Aliases API Wrapper"
  echo ""
  echo "Usage:"
  echo "malias <command> <alias>"
  echo ""
  echo "Commands:"
  echo "add        Create a new alias"
  echo "del        Delete an existing alias"
  echo ""
  echo "Config file:"
  echo "$CONF_PATH"
  exit
fi

# Check dependencies
if [[ -x curl ]]; then
  echo "curl seems to be missing, please install before using this script."
  exit 1
fi


# Check for existence of config file
if [ ! -s "$CONF_PATH" ]; then
  echo "Config file not found, please create the file at $CONF_PATH"
  echo "An example config file has been created for you at: $CONF_PATH.example"

  EXAMPLE_CONF_PATH=$CONF_PATH.example
  echo -n "" > $EXAMPLE_CONF_PATH
  echo "USE_OTP=false # If your you use 2FA with your account, enable this setting" > $EXAMPLE_CONF_PATH
  echo "OTP_CMD=\$(cloak view mailinabo) # Command to get 2FA token" >> $EXAMPLE_CONF_PATH
  echo 'USER_EMAIL="user@domain.com"' >> "$CONF_PATH.example"
  echo 'USER_PASSWORD="passw0rd!" # Or you can use a command to get the password from a password manager' >> $EXAMPLE_CONF_PATH
  echo '                          # e.g: USER_PASSWORD=$(gopass show -o mailinabox)' >> $EXAMPLE_CONF_PATH
  echo 'FORWARD_TO="forward@domain.com"' >> $EXAMPLE_CONF_PATH
  echo 'HOST="https://box.domain.com/admin"' >> $EXAMPLE_CONF_PATH
  echo 'API_KEY_FILE=/tmp/mbox_api_key' >> $EXAMPLE_CONF_PATH
  exit 1
else
. $CONF_PATH
fi

# Check config file validity
if [[ -z "$USE_OTP" ]]; then
  echo "Missing USE_OTP declaration in config file!"
  exit 1
fi
if [[ ! -z "$USE_OTP" ]]; then
  if [[ -z "$OTP_CMD" ]]; then
    echo "Missing OTP_CMD declaration in config file!"
    exit 1
  fi
fi
if [[ -z "$USER_EMAIL" ]]; then
  echo "Missing USER_EMAIL declaration in config file!"
  exit 1
fi
if [[ -z "$USER_PASSWORD" ]]; then
  echo "Missing USER_PASSWORD declaration in config file!"
  exit 1
fi
if [[ -z "$FORWARD_TO" ]]; then
  echo "Missing FORWARD_TO declaration in config file!"
  exit 1
fi
if [[ -z "$HOST" ]]; then
  echo "Missing HOST declaration in config file!"
  exit 1
fi
if [[ -z "$API_KEY_FILE" ]]; then
  API_KEY_FILE=/tmp/mbox_api_key
fi

COMMAND=$1
ALIAS=$2
STALE_API_KEY_ERROR="Incorrect email address or password."

# Generate new API key
get_api_key() {
  curl -s -X POST "$HOST/login" -H "x-auth-token: $OTP_CMD" -u "$USER_EMAIL:$USER_PASSWORD" | jq -r ".api_key"
}

# Renew API key when it's stale
renew_api_key_if_stale() {
  privilege_test=$(curl -s "$HOST/mail/users/privileges?email=$USER_EMAIL" -u "$USER_EMAIL:`stored_api_key`")
  if [[ "$privilege_test" == $STALE_API_KEY_ERROR ]]; then
    get_api_key > $API_KEY_FILE
  fi
}

# Get API key from tmp file
stored_api_key() {
  cat $API_KEY_FILE
}

add_alias() {
  curl -s -X POST "$HOST/mail/aliases/add" -d "address=$ALIAS" -d "forwards_to=$FORWARD_TO" -u "$USER_EMAIL:`stored_api_key`"
}

remove_alias() {
  curl -s -X POST "$HOST/mail/aliases/remove" -d "address=$ALIAS" -u "$USER_EMAIL:`stored_api_key`"
}

# Store API key in a tmp file and reuse it if it exists
if [ ! -s "$API_KEY_FILE" ]; then
  get_api_key > $API_KEY_FILE
fi

renew_api_key_if_stale

case $COMMAND in
  add)
    output=$(add_alias)
    if [[ add_alias != "alias added" ]]; then
      echo "Alias added successfully: $ALIAS"
    else
      echo "Adding alias failed!"
      exit 1
    fi
    ;;

  del)
    output=$(remove_alias)
    if [[ "$output" == "alias removed" ]]; then
      echo "Alias removed successfully"
    else
      echo "Removing alias failed: $output"
      exit 1
    fi
    ;;

  *)
    echo "Unknown command!"
    exit 1
    ;;
esac
