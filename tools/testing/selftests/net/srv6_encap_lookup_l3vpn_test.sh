#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# author: Andrea Mayer <andrea.mayer@uniroma2.it>

# This test is designed for evaluating the SRv6 encap "lookup" attribute used
# for controlling the FIB table in which the post-encap SID is resolved.
#
# The topology is the same as srv6_end_dt6_l3vpn_test.sh: two different
# tenants (named 100 and 200) offer IPv6 L3 VPN services allowing hosts to
# communicate with each other across an IPv6 network.
#
# Each VRF has default blackhole routes (IPv4 and IPv6) so that any
# traffic without a matching route in the VRF is dropped.  Without the
# "lookup" attribute, the post-encap SID resolution would hit the
# blackhole and the packet would be dropped.  The encap routes use
# "lookup 254" to direct the SID resolution to the main table where the
# SID route is installed.
#
# Of course, the IPv6 L3 VPN for tenant 200 works exactly as the IPv6 L3 VPN
# for tenant 100. In this case, only hosts hs-t200-3 and hs-t200-4 are able to
# connect with each other.
#
#
# +-------------------+                                   +-------------------+
# |                   |                                   |                   |
# |  hs-t100-1 netns  |                                   |  hs-t100-2 netns  |
# |                   |                                   |                   |
# |  +-------------+  |                                   |  +-------------+  |
# |  |    veth0    |  |                                   |  |    veth0    |  |
# |  |  cafe::1/64 |  |                                   |  |  cafe::2/64 |  |
# |  +-------------+  |                                   |  +-------------+  |
# |        .          |                                   |         .         |
# +-------------------+                                   +-------------------+
#          .                                                        .
#          .                                                        .
#          .                                                        .
# +-----------------------------------+   +-----------------------------------+
# |        .                          |   |                         .         |
# | +---------------+                 |   |                 +---------------- |
# | |   veth-t100   |                 |   |                 |   veth-t100   | |
# | |  cafe::254/64 |    +----------+ |   | +----------+    |  cafe::254/64 | |
# | +-------+-------+    | localsid | |   | | localsid |    +-------+-------- |
# |         |            |   table  | |   | |   table  |            |         |
# |    +----+----+       +----------+ |   | +----------+       +----+----+    |
# |    | vrf-100 |                    |   |                    | vrf-100 |    |
# |    +---------+     +------------+ |   | +------------+     +---------+    |
# |                    |   veth0    | |   | |   veth0    |                    |
# |                    | fd00::1/64 |.|...|.| fd00::2/64 |                    |
# |    +---------+     +------------+ |   | +------------+     +---------+    |
# |    | vrf-200 |                    |   |                    | vrf-200 |    |
# |    +----+----+                    |   |                    +----+----+    |
# |         |                         |   |                         |         |
# | +-------+-------+                 |   |                 +-------+-------- |
# | |   veth-t200   |                 |   |                 |   veth-t200   | |
# | |  cafe::254/64 |                 |   |                 |  cafe::254/64 | |
# | +---------------+      rt-1 netns |   | rt-2 netns      +---------------- |
# |        .                          |   |                          .        |
# +-----------------------------------+   +-----------------------------------+
#          .                                                         .
#          .                                                         .
#          .                                                         .
#          .                                                         .
# +-------------------+                                   +-------------------+
# |        .          |                                   |          .        |
# |  +-------------+  |                                   |  +-------------+  |
# |  |    veth0    |  |                                   |  |    veth0    |  |
# |  |  cafe::3/64 |  |                                   |  |  cafe::4/64 |  |
# |  +-------------+  |                                   |  +-------------+  |
# |                   |                                   |                   |
# |  hs-t200-3 netns  |                                   |  hs-t200-4 netns  |
# |                   |                                   |                   |
# +-------------------+                                   +-------------------+
#
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~
# | Network configuration |
# ~~~~~~~~~~~~~~~~~~~~~~~~~
#
# rt-1: localsid table (table 90)
# +-------------------------------------------------+
# |SID              |Action                         |
# +-------------------------------------------------+
# |fc00:21:100::6006|apply SRv6 End.DT6 vrftable 100|
# +-------------------------------------------------+
# |fc00:21:200::6006|apply SRv6 End.DT6 vrftable 200|
# +-------------------------------------------------+
#
# rt-1: main table (table 254) - post-encap SID resolution
# +---------------------------------------------------+
# |SID                |Action                         |
# +---------------------------------------------------+
# |fc00:12:100::6006  |forward via fd00::2 dev veth0  |
# +---------------------------------------------------+
# |fc00:12:200::6006  |forward via fd00::2 dev veth0  |
# +---------------------------------------------------+
#
# rt-1: VRF tenant 100 (table 100)
# +----------------------------------------------------------------+
# |host       |Action                                              |
# +----------------------------------------------------------------+
# |cafe::2    |apply seg6 encap segs fc00:12:100::6006 lookup 254  |
# +----------------------------------------------------------------+
# |cafe::/64  |forward to dev veth_t100                            |
# +----------------------------------------------------------------+
# |default    |blackhole (IPv4 and IPv6)                            |
# +----------------------------------------------------------------+
#
# rt-1: VRF tenant 200 (table 200)
# +----------------------------------------------------------------+
# |host       |Action                                              |
# +----------------------------------------------------------------+
# |cafe::4    |apply seg6 encap segs fc00:12:200::6006 lookup 254  |
# +----------------------------------------------------------------+
# |cafe::/64  |forward to dev veth_t200                            |
# +----------------------------------------------------------------+
# |default    |blackhole (IPv4 and IPv6)                            |
# +----------------------------------------------------------------+
#
#
# rt-2: localsid table (table 90)
# +-------------------------------------------------+
# |SID              |Action                         |
# +-------------------------------------------------+
# |fc00:12:100::6006|apply SRv6 End.DT6 vrftable 100|
# +-------------------------------------------------+
# |fc00:12:200::6006|apply SRv6 End.DT6 vrftable 200|
# +-------------------------------------------------+
#
# rt-2: main table (table 254) - post-encap SID resolution
# +---------------------------------------------------+
# |SID                |Action                         |
# +---------------------------------------------------+
# |fc00:21:100::6006  |forward via fd00::1 dev veth0  |
# +---------------------------------------------------+
# |fc00:21:200::6006  |forward via fd00::1 dev veth0  |
# +---------------------------------------------------+
#
# rt-2: VRF tenant 100 (table 100)
# +----------------------------------------------------------------+
# |host       |Action                                              |
# +----------------------------------------------------------------+
# |cafe::1    |apply seg6 encap segs fc00:21:100::6006 lookup 254  |
# +----------------------------------------------------------------+
# |cafe::/64  |forward to dev veth_t100                            |
# +----------------------------------------------------------------+
# |default    |blackhole (IPv4 and IPv6)                            |
# +----------------------------------------------------------------+
#
# rt-2: VRF tenant 200 (table 200)
# +----------------------------------------------------------------+
# |host       |Action                                              |
# +----------------------------------------------------------------+
# |cafe::3    |apply seg6 encap segs fc00:21:200::6006 lookup 254  |
# +----------------------------------------------------------------+
# |cafe::/64  |forward to dev veth_t200                            |
# +----------------------------------------------------------------+
# |default    |blackhole (IPv4 and IPv6)                            |
# +----------------------------------------------------------------+
#

# shellcheck source=lib.sh
source lib.sh

readonly LOCALSID_TABLE_ID=90
readonly IPv6_RT_NETWORK=fd00
readonly IPv6_HS_NETWORK=cafe
readonly VPN_LOCATOR_SERVICE=fc00
PING_TIMEOUT_SEC=4

SETUP_ERR=1

ret=${ksft_skip}
nsuccess=0
nfail=0

PAUSE_ON_FAIL=${PAUSE_ON_FAIL:=no}

log_test()
{
	local rc="$1"
	local expected="$2"
	local msg="$3"

	if [ "${rc}" -eq "${expected}" ]; then
		nsuccess=$((nsuccess+1))
		printf "\n    TEST: %-60s  [ OK ]\n" "${msg}"
	else
		ret=1
		nfail=$((nfail+1))
		printf "\n    TEST: %-60s  [FAIL]\n" "${msg}"
		if [ "${PAUSE_ON_FAIL}" = "yes" ]; then
			echo
			echo "hit enter to continue, 'q' to quit"
			read -r a
			[ "$a" = "q" ] && exit 1
		fi
	fi
}

print_log_test_results()
{
	printf "\nTests passed: %3d\n" "${nsuccess}"
	printf "Tests failed: %3d\n"   "${nfail}"

	# when a test fails, the value of 'ret' is set to 1 (error code).
	# Conversely, when all tests are passed successfully, the 'ret' value
	# is set to 0 (success code).
	if [ "${ret}" -ne 1 ]; then
		ret=0
	fi
}

log_section()
{
	echo
	echo "################################################################################"
	echo "TEST SECTION: $*"
	echo "################################################################################"
}

get_rtname()
{
	local rtid="$1"

	echo "rt_${rtid}"
}

get_hsname()
{
	local tid="$1"
	local hsid="$2"

	echo "hs_t${tid}_${hsid}"
}

cleanup()
{
	ip link del veth-rt-1 2>/dev/null || true
	ip link del veth-rt-2 2>/dev/null || true

	cleanup_all_ns

	# check whether the setup phase was completed successfully or not. In
	# case of an error during the setup phase of the testing environment,
	# the selftest is considered as "skipped".
	if [ "${SETUP_ERR}" -ne 0 ]; then
		echo "SKIP: Setting up the testing environment failed"
		exit "${ksft_skip}"
	fi

	exit "${ret}"
}

# Setup the basic networking for the routers
setup_rt_networking()
{
	local id="$1"
	local nsname

	eval nsname=\${$(get_rtname "${id}")}

	ip link set "veth-rt-${id}" netns "${nsname}"
	ip -netns "${nsname}" link set "veth-rt-${id}" name veth0

	ip netns exec "${nsname}" sysctl -wq net.ipv6.conf.all.accept_dad=0
	ip netns exec "${nsname}" sysctl -wq net.ipv6.conf.default.accept_dad=0

	ip -netns "${nsname}" addr add "${IPv6_RT_NETWORK}::${id}/64" dev veth0 nodad
	ip -netns "${nsname}" link set veth0 up
	ip -netns "${nsname}" link set lo up

	ip netns exec "${nsname}" sysctl -wq net.ipv6.conf.all.forwarding=1
}

setup_hs()
{
	local hid="$1"
	local rid="$2"
	local tid="$3"
	local hsname
	local rtname
	local rtveth="veth-t${tid}"

	eval hsname=\${$(get_hsname "${tid}" "${hid}")}
	eval rtname=\${$(get_rtname "${rid}")}

	# set the networking for the host
	ip netns exec "${hsname}" sysctl -wq net.ipv6.conf.all.accept_dad=0
	ip netns exec "${hsname}" sysctl -wq net.ipv6.conf.default.accept_dad=0

	ip -netns "${hsname}" link add veth0 type veth peer name "${rtveth}"
	ip -netns "${hsname}" link set "${rtveth}" netns "${rtname}"
	ip -netns "${hsname}" addr add "${IPv6_HS_NETWORK}::${hid}/64" dev veth0 nodad
	ip -netns "${hsname}" link set veth0 up
	ip -netns "${hsname}" link set lo up

	# configure the VRF for the tenant X on the router which is directly
	# connected to the source host.
	ip -netns "${rtname}" link add "vrf-${tid}" type vrf table "${tid}"
	ip -netns "${rtname}" link set "vrf-${tid}" up

	ip netns exec "${rtname}" sysctl -wq net.ipv6.conf.all.accept_dad=0
	ip netns exec "${rtname}" sysctl -wq net.ipv6.conf.default.accept_dad=0

	# enslave the veth-tX interface to the vrf-X in the access router
	ip -netns "${rtname}" link set "${rtveth}" master "vrf-${tid}"
	ip -netns "${rtname}" addr add "${IPv6_HS_NETWORK}::254/64" dev "${rtveth}" nodad
	ip -netns "${rtname}" link set "${rtveth}" up

	ip netns exec "${rtname}" sysctl -wq "net.ipv6.conf.${rtveth}.proxy_ndp=1"

	ip netns exec "${rtname}" sh -c "echo 1 > /proc/sys/net/vrf/strict_mode"

	# default blackhole routes in the VRF: any traffic that does not
	# match a specific route in the VRF is dropped. Without the
	# "lookup" attribute on the encap route, the post-encap SID
	# cannot be resolved from within the VRF.
	# See Documentation/networking/vrf.rst for the metric convention.
	ip -netns "${rtname}" -6 route add blackhole default metric 4278198272 \
		vrf "vrf-${tid}"
	ip -netns "${rtname}" -4 route add blackhole default metric 4278198272 \
		vrf "vrf-${tid}"
}

setup_vpn_config()
{
	local hssrc="$1"
	local rtsrc="$2"
	local hsdst="$3"
	local rtdst="$4"
	local tid="$5"
	local rtsrc_name
	local rtdst_name
	local rtveth="veth-t${tid}"

	local vpn_sid="${VPN_LOCATOR_SERVICE}:${hssrc}${hsdst}:${tid}::6006"

	eval rtsrc_name=\${$(get_rtname "${rtsrc}")}
	eval rtdst_name=\${$(get_rtname "${rtdst}")}

	ip -netns "${rtsrc_name}" -6 neigh add proxy "${IPv6_HS_NETWORK}::${hsdst}" dev "${rtveth}"

	# set the encap route for encapsulating packets which arrive from the
	# host hssrc and destined to the access router rtsrc.
	ip -netns "${rtsrc_name}" -6 route add "${IPv6_HS_NETWORK}::${hsdst}/128" vrf "vrf-${tid}" \
		encap seg6 mode encap segs "${vpn_sid}" lookup 254 dev veth0
	ip -netns "${rtsrc_name}" -6 route add "${vpn_sid}/128" \
		via "fd00::${rtdst}" dev veth0

	# set the decap route for decapsulating packets which arrive from
	# the rtdst router and destined to the hsdst host.
	ip -netns "${rtdst_name}" -6 route add "${vpn_sid}/128" table "${LOCALSID_TABLE_ID}" \
		encap seg6local action End.DT6 vrftable "${tid}" dev "vrf-${tid}"

	# all sids for VPNs start with a common locator which is fc00::/16.
	# Routes for handling the SRv6 End.DT6 behavior instances are grouped
	# together in the 'localsid' table.
	#
	# NOTE: added only once
	if [ -z "$(ip -netns "${rtdst_name}" -6 rule show | \
	    grep "to ${VPN_LOCATOR_SERVICE}::/16 lookup ${LOCALSID_TABLE_ID}")" ]; then
		ip -netns "${rtdst_name}" -6 rule add \
			to "${VPN_LOCATOR_SERVICE}::/16" \
			lookup "${LOCALSID_TABLE_ID}" prio 999
	fi
}

setup()
{
	ip link add veth-rt-1 type veth peer name veth-rt-2
	# setup the networking for router rt-1 and router rt-2
	setup_ns rt_1 rt_2
	setup_rt_networking 1
	setup_rt_networking 2

	# setup two hosts for the tenant 100.
	#  - host hs-1 is directly connected to the router rt-1;
	#  - host hs-2 is directly connected to the router rt-2.
	setup_ns hs_t100_1 hs_t100_2
	setup_hs 1 1 100  #args: host router tenant
	setup_hs 2 2 100

	# setup two hosts for the tenant 200
	#  - host hs-3 is directly connected to the router rt-1;
	#  - host hs-4 is directly connected to the router rt-2.
	setup_ns hs_t200_3 hs_t200_4
	setup_hs 3 1 200
	setup_hs 4 2 200

	# setup the IPv6 L3 VPN which connects the host hs-t100-1 and host
	# hs-t100-2 within the same tenant 100.
	setup_vpn_config 1 1 2 2 100  #args: src_host src_router dst_host dst_router tenant
	setup_vpn_config 2 2 1 1 100

	# setup the IPv6 L3 VPN which connects the host hs-t200-3 and host
	# hs-t200-4 within the same tenant 200.
	setup_vpn_config 3 1 4 2 200
	setup_vpn_config 4 2 3 1 200

	# testing environment was set up successfully
	SETUP_ERR=0
}

check_rt_connectivity()
{
	local rtsrc="$1"
	local rtdst="$2"
	local nsname

	eval nsname=\${$(get_rtname "${rtsrc}")}

	ip netns exec "${nsname}" ping -c 1 -W 1 "${IPv6_RT_NETWORK}::${rtdst}" \
		>/dev/null 2>&1
}

check_and_log_rt_connectivity()
{
	local rtsrc="$1"
	local rtdst="$2"

	check_rt_connectivity "${rtsrc}" "${rtdst}"
	log_test $? 0 "Routers connectivity: rt-${rtsrc} -> rt-${rtdst}"
}

check_hs_connectivity()
{
	local hssrc="$1"
	local hsdst="$2"
	local tid="$3"
	local nsname

	eval nsname=\${$(get_hsname "${tid}" "${hssrc}")}

	ip netns exec "${nsname}" ping -c 1 -W "${PING_TIMEOUT_SEC}" \
		"${IPv6_HS_NETWORK}::${hsdst}" >/dev/null 2>&1
}

check_and_log_hs_connectivity()
{
	local hssrc="$1"
	local hsdst="$2"
	local tid="$3"

	check_hs_connectivity "${hssrc}" "${hsdst}" "${tid}"
	log_test $? 0 "Hosts connectivity: hs-t${tid}-${hssrc} -> hs-t${tid}-${hsdst} (tenant ${tid})"
}

check_and_log_hs_isolation()
{
	local hssrc="$1"
	local tidsrc="$2"
	local hsdst="$3"
	local tiddst="$4"

	check_hs_connectivity "${hssrc}" "${hsdst}" "${tidsrc}"
	# NOTE: ping should fail
	log_test $? 1 "Hosts isolation: hs-t${tidsrc}-${hssrc} -X-> hs-t${tiddst}-${hsdst}"
}


check_and_log_hs2gw_connectivity()
{
	local hssrc="$1"
	local tid="$2"

	check_hs_connectivity "${hssrc}" 254 "${tid}"
	log_test $? 0 "Hosts connectivity: hs-t${tid}-${hssrc} -> gw (tenant ${tid})"
}

router_tests()
{
	log_section "IPv6 routers connectivity test"

	check_and_log_rt_connectivity 1 2
	check_and_log_rt_connectivity 2 1
}

host2gateway_tests()
{
	log_section "IPv6 connectivity test among hosts and gateway"

	check_and_log_hs2gw_connectivity 1 100
	check_and_log_hs2gw_connectivity 2 100

	check_and_log_hs2gw_connectivity 3 200
	check_and_log_hs2gw_connectivity 4 200
}

host_vpn_tests()
{
	log_section "SRv6 VPN connectivity test among hosts in the same tenant"

	check_and_log_hs_connectivity 1 2 100
	check_and_log_hs_connectivity 2 1 100

	check_and_log_hs_connectivity 3 4 200
	check_and_log_hs_connectivity 4 3 200
}

host_vpn_isolation_tests()
{
	local i
	local j
	local k
	local tmp
	local l1="1 2"
	local l2="3 4"
	local t1=100
	local t2=200

	log_section "SRv6 VPN isolation test among hosts in different tenants"

	for k in 0 1; do
		for i in ${l1}; do
			for j in ${l2}; do
				check_and_log_hs_isolation "${i}" "${t1}" "${j}" "${t2}"
			done
		done

		# let us test the reverse path
		tmp="${l1}"; l1="${l2}"; l2="${tmp}"
		tmp=${t1}; t1=${t2}; t2=${tmp}
	done
}

host_vpn_lookup_tests()
{
	log_section "SRv6 VPN w/o lookup attribute test"

	__test_lookup 1 2 1 100
	__test_lookup 2 1 2 100
	__test_lookup 3 4 1 200
	__test_lookup 4 3 2 200
}

__test_lookup()
{
	local hssrc="$1"
	local hsdst="$2"
	local rtsrc="$3"
	local tid="$4"
	local rtname

	local vpn_sid="${VPN_LOCATOR_SERVICE}:${hssrc}${hsdst}:${tid}::6006"

	eval rtname=\${$(get_rtname "${rtsrc}")}

	# replace encap route without "lookup" attribute
	ip -netns "${rtname}" -6 route replace "${IPv6_HS_NETWORK}::${hsdst}/128" \
		vrf "vrf-${tid}" \
		encap seg6 mode encap segs "${vpn_sid}" dev veth0

	check_hs_connectivity "${hssrc}" "${hsdst}" "${tid}"
	log_test $? 1 "Host broken connectivity w/o lookup: hs-t${tid}-${hssrc} -X-> hs-t${tid}-${hsdst}"

	# restore encap route with "lookup 254" for subsequent tests
	ip -netns "${rtname}" -6 route replace "${IPv6_HS_NETWORK}::${hsdst}/128" \
		vrf "vrf-${tid}" \
		encap seg6 mode encap segs "${vpn_sid}" lookup 254 dev veth0
}

test_command_or_ksft_skip()
{
	local cmd="$1"

	if [ ! -x "$(command -v "${cmd}")" ]; then
		echo "SKIP: Could not run test without \"${cmd}\" tool"
		exit "${ksft_skip}"
	fi
}

test_vrf_or_ksft_skip()
{
	modprobe vrf &>/dev/null || true
	if [ ! -e /proc/sys/net/vrf/strict_mode ]; then
		echo "SKIP: vrf sysctl does not exist"
		exit "${ksft_skip}"
	fi
}

test_encap_lookup_supp_or_ksft_skip()
{
	local nsname

	setup_ns nsname
	ip -netns "${nsname}" link add veth0 type veth \
		peer name veth1 netns "${nsname}"
	ip -netns "${nsname}" link set veth0 up

	if ! ip -netns "${nsname}" -6 route add fc00::1/128 \
			encap seg6 mode encap segs fc00::2 lookup 254 \
			dev veth0 2>/dev/null; then
		cleanup_ns "${nsname}"
		echo "SKIP: seg6 encap lookup attribute not supported"
		exit "${ksft_skip}"
	fi

	cleanup_ns "${nsname}"
}

if [ "$(id -u)" -ne 0 ]; then
	echo "SKIP: Need root privileges"
	exit "${ksft_skip}"
fi

# required programs to carry out this selftest
test_command_or_ksft_skip ip
test_command_or_ksft_skip ping
test_command_or_ksft_skip sysctl
test_command_or_ksft_skip grep

test_vrf_or_ksft_skip
test_encap_lookup_supp_or_ksft_skip

set -e
trap cleanup EXIT

setup
set +e

router_tests
host2gateway_tests
host_vpn_tests
host_vpn_isolation_tests
host_vpn_lookup_tests

print_log_test_results
