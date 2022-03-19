# cloudflare-sh

This script is designed to be use to manage DNS records of multiple accounts and multiple zones. It also prioritize scriptablility and portability.

This script provides cli interface to manage DNS records on cloudflare via cloudflare api with minimum footprint and dependencies. The output of this script in intended to be simple to parse and easy to use with other tools like `awk`

# Installation

The only dependencies are `jq` and `curl`, you need to install `jq` and `curl` for your specific operating system.
After you have installed the dependencies, simply clone the directory or place the shell script somewhere under your `$PATH`. 

# Usage

### Api key / Profile management

You can use this script with and without storing your api keys with this tool, however storing it will make your life much easier and secure. In fact, you can store multiple api keys, and alias them to fit your need. The api keys are always store with `0400` permission so only the owner can read it.

To run any of the command with an explicit api key, you can simply add the `--apikey <cloudflare-key>` option.

Your DNS records lives in a zone, and a zone lives in your account, natuarlly it becomes quite cumbersome when you just want to query / perform changes to some domain. This tool allows you to create different profiles, a profile stores a api key together with a zone, such that you can manage your domain without needing to explicitly specify the api key and zone id you will use.

This script by default stores your configuration under `$HOME/.cloudflare`, this directory will be created automatically when you use the script.

To register your api key
```
# Register our apikey aliased as `foo`
cloudflare.sh apikey new --keyname foo --apikey <cloudflare-api-key>
```

If this is your first time and first api key, the tool automatiaclly set it as the default key so you never have to type in the api again.

To create a profile,

```
cloudflare.sh profile create your-profile-name --keyname your-apikey-name --zone_id <zone-id-of-the-zone>
```

To use a profile in place of api key and zone id, add `--profile your-profile-name` instead of `--keyname your-apikey-name` and `--zone_name example.com`.

In the case when multiple of these variables defined, the precedence are:

`--apikey` (use a api key explicitly) > `--keyname (use a api key by name)` > `--profile (usa a profile)` > `(default zone_id)`

Similarly 
`--zone_id` > `--zone_name` > `--profile (use a profile)` > `(default zone_id)`

### Zone management

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


