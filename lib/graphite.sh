#!/bin/bash

# Collect stats for piping them into graphite
function prepare_graphite_stats() {
	FILE=$1
	TSTAMP=$(date +%s)
	{\
		#Alfred stats
		jq -r '.|to_entries|.[] as $node|{
				loadavg: $node.value.statistics.loadavg,
				uptime: $node.value.statistics.uptime,
				"traffic.forward.bytes": $node.value.statistics.traffic.forward.bytes,
				"traffic.mgmt_rx.bytes": $node.value.statistics.traffic.mgmt_rx.bytes,
				"traffic.rx.bytes": $node.value.statistics.traffic.rx.bytes,
				"traffic.mgmt_tx.bytes": $node.value.statistics.traffic.mgmt_tx.bytes,
				"traffic.tx.bytes": $node.value.statistics.traffic.tx.bytes,
				"rootfs_usage": $node.value.statistics.rootfs_usage,
				"memory.buffers": $node.value.statistics.memory.buffers,
				"memory.total": $node.value.statistics.memory.total,
				"memory.cached": $node.value.statistics.memory.cached,
				"memory.free": $node.value.statistics.memory.free,
				"rootfs_usage": $node.value.statistics.rootfs_usage,
				"online" : (if $node.value.flags.online != null then (if $node.value.flags.online == true then "1" else "0" end) else null end),
				"clientcount" : ($node.value.statistics.clients.total // 0),
				"clients.wifi5" : ($node.value.statistics.clients.wifi5 // 0),
                                "clients.wifi24" : ($node.value.statistics.clients.wifi24 // 0),
                                "clients.wifi" : ($node.value.statistics.clients.wifi // 0),
                                "clients.total" : ($node.value.statistics.clients.total // 0)
			}|to_entries|.[] as $item|select($item.value != null)|"freifunk.nodes."+$node.key+"." + $item.key +" "+($item.value|tostring)+" '$TSTAMP'"' $FILE
	}
}

# Finally pipe the collected stats into graphite
function update_graphite_stats() {
	FILE=$1
	prepare_graphite_stats $FILE | nc -q0 localhost 2003
} 


# Global domain stats
function prepare_graphite_stats_domains() {
	{\
		TSTAMP=$(date +%s)
		wget -qO- http://map.freifunk-ruhrgebiet.de/counts/?json| \
		jq -r '.domaenen+{global: .global}|to_entries as $els|$els[] as $el|{
			"ratio": $el.value.ratio[0],
			"server.max": $el.value.server.max,
			"server.min": $el.value.server.min,
			"tunnel": $el.value.tunnel[0],
			"clients": $el.value.clients[0],
			"nodes.offline" : $el.value.nodes.offline,
			"nodes.online": $el.value.nodes.online
		}|to_entries|.[]|"freifunk.statistics.domains."+$el.key+"."+.key + " " +(.value|tostring)+" '$TSTAMP'"'
	}
}


# Pipe the collected domain stats into graphite
function update_graphite_stats_domains() {
	prepare_graphite_stats_domains | nc -q0 localhost 2003
}


