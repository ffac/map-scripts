#!/bin/bash
# Removes node from state-file

NODE=$1
BASEDIR=/opt/freifunk

if [ "$NODE" != "" ]; then
	jq "[.[]|select(.id !=\""$NODE"\")]" $BASEDIR/ffmap-backend-legacy/state.json > $BASEDIR/ffmap-backend-legacy/state.json.tmp
	mv $BASEDIR/ffmap-backend-legacy/state.json.tmp $BASEDIR/ffmap-backend-legacy/state.json
fi

