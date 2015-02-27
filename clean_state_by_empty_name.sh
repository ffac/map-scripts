#!/bin/bash
# Removes node from state-file

BASEDIR=/opt/freifunk

jq "[.[]|select(.name|length > 0)]" $BASEDIR/ffmap-backend/state.json > $BASEDIR/ffmap-backend/state.json.tmp
mv $BASEDIR/ffmap-backend/state.json.tmp $BASEDIR/ffmap-backend/state.json

