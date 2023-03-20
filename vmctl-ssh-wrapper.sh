#!/bin/sh

# SSH ProxyCommand to launch OpenBSD vmd guests on demand 
#
# Author: Jon Williams <jon@jonwillia.ms>

# https://stackoverflow.com/questions/3222379/how-to-efficiently-convert-long-int-to-dotted-quad-ip-in-bash
INET_NTOA() {
    num=$1
    ip=
    for e in 3 2 1
    do
        quad=`echo "256 ^ $e" | bc`
        if [ -n "$ip" ]
        then
            ip=$ip.
        fi
        ip=$ip`echo "$num / $quad" | bc`
        num=`echo "$num % $quad" | bc`
    done
    ip=$ip.$num
    echo "$ip"
}

INET_ATON()
{
    num=0
    e=3
    saveIFS=$IFS
    IFS=.
    set -- $1
    IFS=$saveIFS
    for ip in "$@"
    do
        num=`echo "$num + $ip * 256 ^ $e" | bc`
        e=`echo "$e - 1" | bc`
    done
    echo "$num"
}


host=$(echo "$1" |sed s/\.vmctl.host$//)
port="$2"

if [ "$host" = "" ] || [ "$port" = "" ]; then
  echo 1>&2 "Usage: $0 <hostname> <port>"
  exit 1
fi

until false; do
  status=$(vmctl status "$host" | awk '(x==1) {print $8} {x=1}')
  echo 1>&2 "$host" status "$status"
  if [ "$status" = "stopped" ] && [ "$did_start" != "1" ]; then
    vmctl start "$host"
    did_start=1
    trap 'vmctl stop "$host"; exit 255' INT QUIT TERM HUP
  else
    if [ "$status" = "running" ] ; then
      break
    fi

    if [ "$status" = "starting" ] ; then
      exit 1
    fi
  fi
  sleep 1
done


host_ip=$(ifconfig tap | awk \
  "(x==1 && /inet /) {print \$2; exit 0}/description: vm.*$host\$/ {x=1} " \
)

long_host_ip=$(INET_ATON "$host_ip")
long_guest_ip=$((long_host_ip+1))
guest_ip=$(INET_NTOA $long_guest_ip)

echo 1>&2 -n "Connecting to $guest_ip:$port "
until nc -z -w 5 "$guest_ip" "$port" > /dev/null 2> /dev/null
do
  echo 1>&2 -n .
  sleep 1
done
echo
echo 1>&2 ssh is up
nc "$guest_ip" "$port"


if [ "$did_start" = "1" ]; then
  vmctl stop "$host"
fi
