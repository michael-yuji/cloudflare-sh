# cloudflare-sh

This script is designed to be use to manage DNS records of multiple accounts and multiple zones. It also prioritize scriptablility and portability, it provides cli interface to manage DNS records on cloudflare via cloudflare api with minimum footprint and dependencies. The output of this script in intended to be simple to parse and easy to use with other tools like `awk`

PR Welcome! See code and bottom of this document for technical documentation.

# Installation

The only dependencies are `jq` and `curl`, you need to install `jq` and `curl` for your specific operating system.
After you have installed the dependencies, simply clone the directory or place the shell script somewhere under your `$PATH`. 

# Usage

```
Usage: cloudflare.sh [options] [CMD] [CMD ARGS...]

  available commands:
    apikey  - Manage api keys
    zone    - Manage zones
    dns     - Manage DNS
    profile - Manage profiles
```

Example workflow

```sh
# register a new api key, since this is your first key, it will become the default now (you can change later)
cloudflare.sh apikey new --keyname test --apikey <your-api-key>

# list DNS records in zone "example.com"
cloudflare.sh dns list --zone_name example.com

# list A records in zone "example.com" 
cloudflare.sh dns list --type A --zone_name example.com

# Create an A record "test.example.com", points to 127.0.0.1
cloudflare.sh dns --zone_name example.com create --type A --name test --content 127.0.0.1

# Same as above, but different ordering, and set priority to 10
cloudflare.sh dns create --zone_name example.com --type A --name test --content 127.0.0.1 --priority 10
```

### Api key / Profile management
You can use this script with and without storing your api keys with this tool, however storing it will make your life much easier and secure. In fact, you can store multiple api keys, and alias them to fit your need. The api keys are always store with `0400` permission so only the owner can read it.

To run any of the command with an explicit api key, you can simply add the `--apikey <cloudflare-key>` option.

```
Usage: apikey [CMD] [options...]

  available commands:

    list
      list all profiles

    new
      Reqister and set a name for an api key
        Required options:
          --apikey  [KEY]  - the api key to store
          --keyname [NAME] - the name of the api key to store as

    set-default [NAME]
      Set the api key with name [NAME] as the default api key, such that when
        executing any other commands without either --apikey or --keyname, the
        default api key will be used

    remove [NAME]
      Remove the api key stored as [NAME]
```

Your DNS records lives in a zone, and a zone lives in your account, natuarlly it becomes quite cumbersome when you just want to query / perform changes to some domain. This tool allows you to create different profiles, a profile stores a api key together with a zone, such that you can manage your domain without needing to explicitly specify the api key and zone id you will use.


```
 Usage: profile [CMD] [options...]
 
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
 ```

This script by default stores your configuration under `$HOME/.cloudflare`, this directory will be created automatically when you use the script.

To register your api key
```
# Register our apikey aliased as `foo`
cloudflare.sh apikey new --keyname foo --apikey <cloudflare-api-key>
```

If this is your first api key, the tool automatiaclly set it as the default key so you never have to type in the api again.

To create a profile,

```
cloudflare.sh profile create your-profile-name --keyname your-apikey-name --zone_id <zone-id-of-the-zone>
```

To use a profile in place of api key and zone id, add `--profile your-profile-name` instead of `--keyname your-apikey-name` and `--zone_name example.com`.

In the case when multiple of these variables defined, the precedence are:

`--apikey` (use a api key explicitly) > `--keyname (use a api key by name)` > `--profile (usa a profile)` > `(default apikey)`

Similarly 
`--zone_id` > `--zone_name` > `--profile (use a profile)` > `(default zone_id)`

### Zone management

```
Usage: zone [CMD] [options...]'

  available commands:

  list
     list all zones

  set-default
    Reqister and set as the default zone
      Required options (either):
        --zone_name [NAME] - the name of the zone to be set for this profile
        --zone_id   [ID]   - the zone id to be set for this profile
```

Current the script only supports querying zones (as that's all I need now).

To query all zones under an account, if you have a default api key set, you can run
```
cloudflare.sh zone list
```

If you have not register an api key, or just want to use with another apikey, you can run
```
cloudflare.sh --apikey <cloudflare-api-key> zone list
```

The command(s) above should give you outputs with format
```
11111111110000000007777abcedfaaa example.org
```

Where the first column is the zone-id and the last column is the zone name.

### DNS management


```
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

```

##### Listing records

To list DNS records under a zone (e.g. example.com), you can run the following command

```
cloudflare.sh dns list --zone_name example.com
```

The output will be in the format of

```
<zone-id> <dns-data (e.g. files.example.com)> <type (e.g. A)> <data (e.g 127.0.0.1)>
```

You can also use `--zone_id` instead of `--zone_name` if you prefer to query dns records within a zone using a zone id instead of the name.

##### Creating/Updating a record

To create a record, you can use one of the following (the example is to create an A record points to 127.0.0.1 for test.example.com)

with a profile:
```cloudflare.sh --profile examplecom dns create --type A --name test --content "127.0.0.1"```

with default apikey and a specific zone name
```cloudflare.sh --zone_name example.com dns create --type A --name test --content "127.0.0.1"```

with explicit apikey and explicit zone_id (... are the arguments to create dns records)
```cloudflare.sh --apikey <cloudflare-key> --zone_id <zone_id> dns create ...```



## The Configuration directory

The layout of the configuration directory is like this:
```
.cloudflare
  | - default
  | - profiles/
  |.   - profiles
  | - keys/
  |.   - your_api_key_name
```

# Technical Documentation

## Calling Cloudflare api
Use the api() function to call the cloudflare api, this will allows api keys
to set automatically, and if there are any api failure it will set shell vars
to aid debugging. The path must be the first argument of the api() function.

Use check_success() function to check if a response succeed. The check_success
function checks if the "success" field of the api returns true.

# fatal failure handling
Use the failure() function to fail the script with an error message, the 
error message will be written to stderr.

## The shell arguments

The way this script works first parse the arguments pass to the script, any
arguments starts with --, for example --foo will strip from the argument list, 
and a shell variable, in this case $foo will be contructed, the value of $foo
will be set to be the value of the next argument.

For example if `--foo bar` are in the argument list, a shell variable foo=bar
will be set.

This allows a good (but can be danger...) degree of flexibility in writing the
script. For example the script contains the logic that if $apikey is not set,
apikey will be derive from other variables, now when the user set --apikey 
directly it will alow us to bypass the deriving logic and save a lot of work.

This is also the reason why must functions does not need to take $1 $2 as arguments.

## Directory structure

When the script launched and after after the script parsed arguments, it will
source "$CF_CONFIG/default" and hence set the default variables, if the user
set the $profile argument, the file in "$CF_CONFIG/profiles/$profile" will be
sourced, and therefore any variables defined in both default and profile will
be shadowed by the values defined in the profile file.







