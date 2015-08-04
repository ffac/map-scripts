#!/bin/bash
# Removes node from state-file

BASEDIR=/opt/freifunk

jq "[.[]|select(.name|length > 0)]" $BASEDIR/ffmap-backend-legacy/state.json > $BASEDIR/ffmap-backend-legacy/state.json.tmp
mv $BASEDIR/ffmap-backend-legacy/state.json.tmp $BASEDIR/ffmap-backend-legacy/state.json

