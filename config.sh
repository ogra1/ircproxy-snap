#! /bin/sh
#
# parse a yaml file and turn it into a bip config
#

set -e

export HOME=$SNAP_DATA

# function to turn yaml into variables
parse_yaml()
{
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_-]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

# get the piped input and store it in a tmpfile
while IFS= read -r LINE; do
    if [ ! "$(id -u)" = "0" ]; then
        echo -n "permission denied (try sudo)"
        exit 1
    fi
    printf "%s\n" "$LINE" >>$SNAP_DATA/.tmp.yaml
done

# if we have permissions, write the different configs
if [ "$(id -u)" = "0" ]; then

    touch $SNAP_DATA/.tmp.yaml
    [ -e $SNAP_DATA/config.yaml ] || \
        cp $SNAP/default.yaml $SNAP_DATA/config.yaml

    # put a header in place
    sed '/^user {.*/,/^};/c\' $SNAP/etc/bip.conf \
        >$SNAP_DATA/bip.conf.head 2>&1

    # get all the vars from yaml
    eval $(parse_yaml $SNAP_DATA/config.yaml)
    eval $(parse_yaml $SNAP_DATA/.tmp.yaml)

    if [ ! -e "$SNAP_DATA/bip.pem" ] || \
        grep -q sslcert $SNAP_DATA/.tmp.yaml; then
        $SNAP/usr/bin/openssl req -new -newkey rsa:4096 -nodes -x509 \
            -subj "/C=$config_ircproxy_sslcert_country/ST=\
$config_ircproxy_sslcert_state/L=\
$config_ircproxy_sslcert_locality/O=\
$config_ircproxy_sslcert_org/CN=\
$config_ircproxy_sslcert_domain" \
            -keyout $SNAP_DATA/bip.pem \
            -out $SNAP_DATA/bip.pem >/dev/null 2>&1
        chmod 600 $SNAP_DATA/bip.pem
    fi

    # put a new config.yaml in place
    cat << EOF >$SNAP_DATA/config.yaml
config:
  ircproxy:
    port: $config_ircproxy_port
    networks: $config_ircproxy_networks
    clientssl: $config_ircproxy_clientssl
    sslcert:
      country: $config_ircproxy_sslcert_country
      state: $config_ircproxy_sslcert_state
      locality: $config_ircproxy_sslcert_locality
      org: $config_ircproxy_sslcert_org
      domain: $config_ircproxy_sslcert_domain
    user:
      nick: $config_ircproxy_user_nick
      user: $config_ircproxy_user_user
      realname: $config_ircproxy_user_realname
      password: $config_ircproxy_user_password
      connections: $config_ircproxy_user_connections
EOF

    # create the actual bip configuration
    sed "s:^client_side_ssl.*:client_side_ssl = $config_ircproxy_clientssl;:" \
        $SNAP_DATA/bip.conf.head >$SNAP_DATA/bip.conf
    sed "s:^port.*:port = $config_ircproxy_port;:" \
        $SNAP_DATA/bip.conf >$SNAP_DATA/bip.conf.tmp
    mv $SNAP_DATA/bip.conf.tmp $SNAP_DATA/bip.conf

    if [ ! "$config_ircproxy_networks" = "[]" ]; then
        echo $config_ircproxy_networks| \
            sed "s/\][ ]*,[ ]*\[/\\n/g;s/\(\]\)//g;s/\(\[\)//g;s/\x27//g;s/,/\t/g"| \
            while read -r line; do
            name=$(echo $line|cut -d' ' -f1)
            host=$(echo $line|cut -d' ' -f2)
            port=$(echo $line|cut -d' ' -f3)
            echo "network {" >>$SNAP_DATA/bip.conf
            echo "    name = \"$name\";" >>$SNAP_DATA/bip.conf
            echo "    server { host = \"$host\";  port = $port; };" >>$SNAP_DATA/bip.conf
            echo "};" >>$SNAP_DATA/bip.conf
        done
    fi
    cat << EOF >>$SNAP_DATA/bip.conf
user {
        name = "$config_ircproxy_user_nick";
        password = "$config_ircproxy_user_password";
        ssl_check_mode = "none";
        default_nick = "$config_ircproxy_user_nick";
        default_user = "$config_ircproxy_user_user";
        default_realname = "$config_ircproxy_user_realname";
EOF
    if [ ! "$config_ircproxy_user_connections" = "[]" ]; then
        echo $config_ircproxy_user_connections| \
            sed "s/\][ ]*,[ ]*\[/\\n/g;s/\(\]\)//g;s/\(\[\)//g;s/\x27//g;s/,/\t/g"| \
            while read -r line; do
            network=$(echo $line|cut -d' ' -f1)
            channels=$(echo $line|sed "s/^$network //;s/ /,/g")
            echo "        connection {" >>$SNAP_DATA/bip.conf
            echo "            name = \"$network\";" >>$SNAP_DATA/bip.conf
            echo "            network = \"$network\";" >>$SNAP_DATA/bip.conf
            echo "            channel { name = \"$channels\";};" >>$SNAP_DATA/bip.conf
            echo "        };" >>$SNAP_DATA/bip.conf
        done
    fi
    echo "};" >>$SNAP_DATA/bip.conf

    chmod 0640 $SNAP_DATA/bip.conf

    # flush the tmpfile
    >$SNAP_DATA/.tmp.yaml
fi

cat $SNAP_DATA/config.yaml|sed 's/password: .*/password: \*\*\* hidden \*\*\*/'
