#!/bin/sh

: ${CF_CONFIG:="$HOME/.cloudflare"}
: ${CF_BASE_URL:="https://api.cloudflare.com/client/v4"}

# some shell implement their own echo that does not support -n 
echo() {
  /usr/bin/env echo $@
}

# escape the variable into something we can put in json
esc() {
  printf "%q" "$1"
}

set_keyval() {
  tag=$1
  file=$2
  key=$3
  value=$4

  echo "[$tag]: $key -> $value"

  if [ ! -z "$(grep -F "$key=" "$file")" ]; then
    sed -i .bak "s/^$key=.*$//g" "$file"
  fi

  echo "$key=$value" >> "$file"
}

# append or replace $key=$value line in the CF_CONFIG/default file
# this file will be source by this script to set variables with their
# default value
set_default() {
  set_keyval "default" "$CF_CONFIG/default" $1 $2
#  key=$1
#  value=$2
#
#  echo "[default]: $key -> $value"
#
#  if [ ! -z "$(grep -F "$key=" "$CF_CONFIG/default")" ]; then
#    sed -i .bak "s/^$key=.*$//g" "$CF_CONFIG/default"
#  fi
#
#  echo -n "$key=$value" >> "$CF_CONFIG/default"
}

# Setup the $apikey variable by the following order:
# user override > explicit profile > default profile
stage_api_key() {
  # if the user explicitly passed in an api key, use it
  # otherwise, if user specified an $keyname (which is name to a stored api key),
  # we retrieve the stored api key from it, if $keyname is also not defined,
  # we lookup the default account and cat the api key from storage
  if [ -z "$apikey" -a -z "$keyname" -a -z "$default_acc" ]; then
    failure "[apikey]: neither \$apikey, \$keyname, nor a default account defined"
  else
    apikey="${apikey:="$(cat $CF_CONFIG/keys/${keyname:="$default_acc"})"}"
  fi
}

# make an api call, this will automatiaclly add -s and apikey to curl so the
# use site can be cleaner, optionally, this set up some variable use for 
# debug api related issues
#
# Usage: api /some/paths?arg=something... [more curl options...]
api() {
  uri=$1
  shift 1
  stage_api_key

  _authheader="Authorization: Bearer $apikey"

  # set the request variable for debugging
  request="curl -s $curlopts -H \"$_authheader\" $CF_BASE_URL$uri $@"
  result="$(curl -s $curopts -H "$_authheader" $CF_BASE_URL$uri $@)"
  
  if [ "$(echo "$result" | jq .success)" = "true" ]; then
    echo -n "$result"
  else
    echo "$?"
    last_api_error="$request\n$result"  
    failure "$result"
  fi
}

# Check if the api request has succeed (cloudflare but a "success" key on the
# top level of response)
check_success() {
  [[ "$(echo "$1" | jq .success)" == "true" ]]
}

failure() {
  >&2 echo "$1"
#  >&2 echo "last_request: $request"
  exit 1
}

# This is a hack to get and consume the arguments without actually looping 
# for all cases nor need need to have sub commands to parse for arguments
# For example if the user entered $0 --key value, a shell variable
# $key will be defined and can be use directly in the sub commands
parse_env() {
  args=""
  while [ "$#" -ne 0 ]; do
    case $1 in
      --_*)
        # We do not want user to override internal variables (start with _)
        failure "cannot override variables starts with _ (on $1)"
        ;;
      --*)
        eval "${1#--}=\"${2?:\"Expected value after $1\"}\""
        shift 2
        ;;
      *)
        args="$args $1"
        shift 1
        ;;
    esac
  done
}

## Profile related ###

# Register new apikey new as alias
apikey_new() {
  keyname="${keyname?:"missing argument --keyname NAME"}"
  apikey="${apikey?:"missing argument --apikey $apikey"}"

  if [ ! -d "$CF_CONFIG/keys" ]; then
    if [ -e "$CF_CONFIG/keys" ]; then
      failure "$CF_CONFIG/keys already exists but is not a directory"
    fi

    mkdir -p "$CF_CONFIG/keys"
  fi

  echo "Validating key..."

  response="$(api /user/tokens/verify)"

  if check_success "$response"; then
    echo "Registering api key as $keyname"
    echo "$apikey" > "$CF_CONFIG/keys/$keyname"
    chmod 0400 "$CF_CONFIG/keys/$keyname"
    if [ -z "$default_acc" ]; then
      echo "default key not found, setting $keyname to be the default key"
      set_default "default_acc" "$keyname"
    fi
  else
    failure "Invalid api key, abort"
  fi
}

apikey_set_default() {
  keyname="${keyname?:"missing argument --keyname NAME"}"

  if [ -e "$CF_CONFIG/keys/$keyname" ]; then
    failure "existing api key with name $keyname does not exist"
  fi

  apikey="$(echo -n "$CF_CONFIG/keys/$keyname")"
  set_default "default_acc" "$keyname"
}

apikey_list() {
  ls -1 "$CF_CONFIG/keys"
}

apikey_remove() {

  if [ -z "$1" ]; then
    failure "No key name supplied"
  fi

  if [ ! -e "$CF_CONFIG/keys/$1" ]; then 
    failure "Such api key with name $1 does not exists"
  fi
  rm "$CF_CONFIG/keys/$1"
}

apikey_help() {
  cat <<EOF
Usage: apikey [CMD] [options...]'

  available commands:

    list
      list all profiles

    new 
      Reqister and set a name for an api key
        Required options:
          --apikey [KEY]  - the api key to store
          --name   [NAME] - the name of the api key to store as

    set-default [NAME]
      Set the api key with name [NAME] as the default api key, such that when
        executing any other commands without either --apikey or --keyname, the 
        default api key will be used

    remove [NAME]
      Remove the api key stored as [NAME]

EOF
}

apikey_main() {
  case $1 in
    help)
      ;;
    new)
      apikey_new
      ;;
    list)
      apikey_list
      ;;
    set-default)
      apikey_set_default
      ;;
    remove)
      apikey_remove $1
      ;;
    *)
      apikey_help
      echo "Unknown subcommand $1"
      ;;
  esac
}

### Profile related ###
profile_create() {
  name="${1?:"Missing required argument: create \"NAME\""}"

  if [ -e "$CF_CONFIG/profiles/$name" ]; then
    failure "The profile $name already exists!"
  fi

  touch "$CF_CONFIG/profiles/$name"
  
  stage_zone_id

  if [ ! -z "$keyname" ]; then 
    set_keyval "$name" "$CF_CONFIG/profiles/$name" "default_acc" "$keyname"
  fi

  if [ ! -z "$zone_id" ]; then
    set_keyval "$name" "$CF_CONFIG/profiles/$name" "default_zone_id" "$zone_id"
  fi
}

profile_help() {
  cat <<EOF
Usage: profile [CMD] [options...]'

  available commands:

  list
     list all profiles

  create [NAME]
    Reqister and set a name for a profile
      Optional options:
        --keyname [NAME]    - the api key name for this profile
        --zone_name [NAME] - the name of the zone to be set for this profile
        --zone_id   [ID]   - the zone id to be set for this profile

  update-zone [NAME]
    Update the zone of a profile with [NAME]

  update-key [NAME]
    Update the apikey use by the profile with [NAME]

  remove [NAME]
    Remove the api key stored as [NAME]

EOF
}

profile_update_zone() {
  if [ -z "$1" ]; then
    failure "profile not defined"
  fi

  if [ ! -e "$CF_CONFIG/profiles/$1" ]; then
    failure "profile $1 does not exist"
  fi

  stage_zone_id

  if [ ! -z "$zone_id" ]; then
    set_keyval "$1" "$CF_CONFIG/profiles/$1" "default_zone_id" "$zone_id"
  else
    failure "No usable --zone_id or --zone_name found"
  fi
}

profile_update_key() {
  if [ -z "$1" ]; then
    failure "profile not defined"
  fi

  if [ ! -e "$CF_CONFIG/profiles/$1" ]; then
    failure "profile $1 does not exist"
  fi

  stage_api_key

  if [ ! -z "$keyname" ]; then
    set_keyval "$1" "$CF_CONFIG/profiles/$1" "default_acc" "$keyname"
  else
    failure "No usable --keyname found"
  fi
}

profile_main() {

  if [ ! -e "$CF_CONFIG/profiles" ]; then
    mkdir -p "$CF_CONFIG/profiles"
  fi

  case $1 in
    help)
      profile_help
      ;;
    list)
      ls -1 "$CF_CONFIG/profiles"
      ;;
    create)
      shift 1
      profile_create $1
      ;;
    update-zone)
      shift 1
      profile_update_zone $1
      ;;
    update-key)
      shift 1
      profile_update_key $1
      ;;
    remove)
      shift 1
      if [ -z "$1" ]; then
        echo "Missing profile name"
        profile_help
      else
        rm "$CF_CONFIG/profiles/$name"
      fi
      ;;
    *)
      profile_help
      ;;
  esac
}

### Zone related ###

stage_zone_id() {
  if [ -z "$zone_id" ]; then
    if [ -z "$zone_id" -a -z "$zone_name" -a -z "$default_zone_id" ]; then
      failure "[zone_id]: neither \$zone_id, \$zone_name, nor a default zone defined"
    else
      if [ ! -z "$zone_name" ]; then
        zone_id=$(zone_list | grep -F "$zone_name" | awk '{ print $1 }')
        if [ -z "$zone_id" ]; then
          failure "Cannot find such zone"
        fi
      else
        zone_id="$default_zone_id"
      fi
    fi
  fi
}

zone_list() {
  response="$(api /zones)"

  if check_success "$response"; then
    echo "$response" | jq -r '.result[] | [.id,.name] | @tsv' | column -t -s $'\t'

  else
    failure "api error: $response"
  fi
}

zone_set_default() {
  stage_zone_id
  if [ -z "zone_id" ]; then
    echo "usage:"
    echo "  set-default --zone_name mydomain.com"
    echo "  set-default --zone_id   000000000000"
    exit 1
  else
    set_default "default_zone_id" "$zone_id"
  fi
}

zone_main() {
  case $1 in
    list)
      zone_list
    ;;
    set-default)
      zone_set_default
    ;;
    *)
      failure "Unknown subcommand $1"
    ;;
  esac
}

### DNS ###

dns_list() {
  stage_zone_id

  _params="per_page=500"

  if [ ! -z "$direction" ]; then
    _params="$_params&direction=$direction"
  fi

  if [ ! -z "$type" ]; then
    _params="$_params&type=$type"
  fi

  if [ ! -z "$proxied" ]; then
    _params="$_params&proxied=$proxied"
  fi

  if [ ! -z "$content" ]; then
    _params="$_params&content=$content"
  fi

  if [ ! -z "$name" ]; then
    _params="$_params&name=$name"
  fi

  response="$(api "/zones/$zone_id/dns_records?$_params")"
  if check_success "$response"; then
    echo "$response" | jq -r ".result[] | [.id, .name, .type, .content ] | @tsv" | column -t -s $'\t'
  else
    echo "api error: $response"
  fi
}

dns_create() {
  stage_zone_id
  # optional parameters
  priority=${priority:=10}
  proxied=${proxied:="false"}
  ttl=${ttl:=1}

  # required parameters
  type=${type?:"Required parameter 'type' missing, pass it by adding --type YOUR_DNS_RECORD_TYPE"}
  name=${name?:"Required parameter 'name' missing, pass it by adding --name YOUR_RECORD_NAME"}
  content=${content?:"Required parameter 'content' missing, pass it by adding --content YOUR_DNS_CONTENT"}

  resp=$(api "/zones/$zone_id/dns_records" -X POST -H "content-type: application/json" \
    --data-binary @- <<EOF
    {
      "type": "$(esc "$type")",
      "name": "$(esc "$name")",
      "content": "$(esc "$content")",
      "ttl": $ttl,
      "priority": $priority,
      "proxied": $proxied
    }
EOF
)
  echo "$resp" | jq '.result'
}

dns_update() {
  record=$1
  stage_zone_id
  # optional parameters
  priority=${priority:=10}
  proxied=${proxied:="false"}
  ttl=${ttl:=1}

  # required parameters
  type=${type?:"Required parameter 'type' missing, pass it by adding --type YOUR_DNS_RECORD_TYPE"}
  name=${name?:"Required parameter 'name' missing, pass it by adding --name YOUR_RECORD_NAME"}
  content=${content?:"Required parameter 'content' missing, pass it by adding --content YOUR_DNS_CONTENT"}

  resp=$(api "/zones/$zone_id/dns_records/$record" \
    -X PUT -H "content-type: application/json" \
    --data-binary @- <<EOF
    {
      "type": "$(esc "$type")",
      "name": "$(esc "$name")",
      "content": "$(esc "$content")",
      "ttl": $ttl,
      "priority": $priority,
      "proxied": $proxied
    }
EOF
)
  echo "$resp" | jq '.result'
}

dns_delete() {
  record=$1
  stage_zone_id
  api "/zones/$zone_id/dns_records/$record" -X DELETE 
}

dns_help() {
  cat <<EOF
Usage: dns [CMD] [options...]'

  common options:
    --apikey    [KEY]     - use alternate api key
    --keyname   [NAME]    - the key name to an api key to use
    --zone_id   [ZONEID]  - operate in another zone by id
    --zone_name [NAME]    - operate in another zone by zone name

  available commands:

    list
      List DNS records,
        Optional options:
          --direction [asc/desc]   - ordering of the records (default desc)
          --type      [TYPE]       - list records with [TYPE]
          --content   [DATA]       - filter by DNS data
          --proxied   [true/false] - filter by if the cloudflare proxy enabled
          --name      [NAME]       - filter by dns name

    update RECORD_ID
        Required and optional options as same as 'create' action 

    create
        Required options:
          --type    [TYPE]  - DNS record type, for example "A"
          --name    [NAME]  - DNS record name, for example "subdomain"
          --content [DATA]  - DNS data, for example "127.0.0.1"
        Optional options:
          --priority [PRIOV]      - DNS priority, for example 10 (default 10)
          --proxied  [true/false] - Enable/disable cloudflare proxy (default false)
          --ttl      [NUM]        - time to live, see cloudflare api for valid values (default 1 (auto))

    delete RECORD_ID 
      - Delete a record by RECORD_ID 

EOF
}

dns_main() {
  case $1 in
    list)
      dns_list
      ;;
    create)
      dns_create
      ;;
    delete)
      if [ -z "$2" ]; then
        failure "Missing argument RECORD_ID"
      fi
      dns_delete $2
      ;;
    update)
      if [ -z "$2" ]; then
        failure "Missing argument RECORD_ID"
      fi
      dns_update $2
      ;;
    help)
      dns_help
      ;;
    *)
      dns_help
      failure "Unknown subcommand $1"
      ;;
  esac
}

trap exit 1

### Entry ###
if [ ! -e "$CF_CONFIG" ]; then
  echo 'creating ~/.cloudflare to store cloudflare configurations'
  mkdir -p "$CF_CONFIG/keys"
fi

if [ ! -e "$CF_CONFIG/default" ]; then
  touch "$CF_CONFIG/default"
else
  source "$CF_CONFIG/default"
fi

# "eats" $@, strip off --* and reserialize them to $args
parse_env $@ 

if [ ! -z "$profile" ]; then
  # Shadow the default profile if user defined a profile
  source "$CF_CONFIG/profiles/$profile"
fi

main() {
  case $1 in
    apikey)
      shift 1
      apikey_main $@
      ;;
    zone)
      shift 1
      zone_main $@
      ;;
    dns)
      shift 1
      dns_main $@
      ;;
    profile)
      shift 1
      profile_main $@
      ;;
    *)
      failure "Unkown command $1, available subcommands: apikey profile zone dns"
    ;;
  esac
}

main $args
