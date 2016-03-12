#!/bin/bash

BASEDIR=/opt/freifunk

SCRIPTSDIR=$BASEDIR"/scripts"

DATADIR=$BASEDIR"/data"
[ -d $DATADIR ] || mkdir -p $DATADIR

LOCKDIR=$BASEDIR"/lock"
[ -d $LOCKDIR ] || mkdir -p $LOCKDIR

LOCKFILE=$LOCKDIR"/cron.lock"


# Include graphite stuff
. $SCRIPTSDIR"/lib/graphite.sh"

# Main entry point
(
	# Wait for lock for 10 seconds
	flock -x -w 10 200 || exit 1

	# Fetch nodes.json from hopglass server (unfiltered, to allow contact address lookups)
	/usr/bin/curl -s --globoff "http://[::1]:4000/nodes.json" > $DATADIR"/nodes-unfiltered.json"

	# Filter and remove contact information
	/usr/bin/jq -c ".nodes |= map(del (.nodeinfo.owner))" $DATADIR"/nodes-unfiltered.json" > $DATADIR"/nodes.json.new" && /bin/mv $DATADIR"/nodes.json.new" $DATADIR"/nodes.json"

	# Fetch hosts for node lookup
	/usr/bin/curl -s --globoff "http://[::1]:4000/hosts" | sed -e 's/$/.nodes.ffac/' > $DATADIR"/hosts"

	# Fetch raw json for collecting the stats to pipe them into graphite
	/usr/bin/curl -s --globoff "http://[::1]:4000/raw.json" > $DATADIR"/raw.json"

	# Update graphite stats
	update_graphite_stats $DATADIR"/raw.json"

) 200>$LOCKFILE


LOCKFILE=$LOCKDIR"/cron.external.lock"
(
        # Wait for lock for 10 seconds
        flock -x -w 10 201 || exit 1

#	update_graphite_stats_domains

) 201>$LOCKFILE

