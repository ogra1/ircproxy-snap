# ircproxy

A simple ircproxy built around bip

## Configuration

The snap puts a default configuration in place and generates a fresh ssl key on first startup

sudo vi /var/snap/ircproxy/current/bip.conf
sudo snap restart ircproxy

To generate an IRC password to use with the config the snap also ships the "ircproxy.bipmkpw" tool.

## Building

Just clone this tree and run snapcraft in the toplevel dir
