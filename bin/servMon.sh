#!/bin/bash

# Sample shell script that provides host (and services) monitoring with ApMon.
#
# 2007-06-07
# Catalin.Cirstoiu@cern.ch
#
# Rewritten the logic behind pidfiles and "stay alive" mechanism
# May 2010
# Fabrizio Furano

[[ ! -e "/bin/ps" ]] && echo "need ps to function; yum -y install procps" && exit 1

usage(){
	cat <<EOM
usage: servMon.sh [[-f|-k] -p pidfile] hostGroup [serv1Name pid1] ...
     -p pidfile   - put ApMon's PID in this file and run in background. If
                    pidfile already contains a running process, just exit.
	-f        - kill previous background-running ApMon with the same pidfile
	            and will start a new one with the new parameters
	-k        - just kill previous background-running ApMon
	hostGroup - base name for the host monitoring
	servXName - name of the X'th service
	pidX      - pid of the X'th service
EOM
	exit 1
}

# Get the machine's hostname
host=`hostname -f`
userid=`id -u`

[[ $# -eq 0 ]] && usage

hostGroup=
newline="
"

while [ $# -gt 0 ] ; do
	case "$1" in
		-f)
			force=1   # Set the force flag
			;;
		-k)
			force=1
			justKill=1
			;;
		-p)
			pidfile=$2 # Set the pidfile
			shift
			;;
		-*)
			echo -e "Invalid parameter '$1'\n"
			usage
			;;
		*)
			if [ -z "$hostGroup" ] ; then
				hostGroup=$1 # First bareword is the host group, for host monitoring
			else
				if [ -n "$2" ] ; then
					srvMonCmds="${srvMonCmds}${newline}\$apm->addJobToMonitor($2, '', '${1}_Services', '$host');"
					shift
				else
					echo -e "Service '$1' needs pid number!\n"
  				usage
				fi
			fi
	esac
	shift
done

KillAllApMon() {
for nm in `find $pidfile* 2>/dev/null` ; do
  pid=`cat $nm`
  echo "Killing previous ApMon instance with pid $pid ..."
  kill -9 $pid 2>/dev/null
  rm $nm
done
}

# If pidfile was given, check the supposedly running processes
# pidfile is the prefix which is given to the pidfiles
#
# If they are too many, kill them all (and remove the pidfiles)
# If 'force' kill them all (and remove the pidfiles)

# If pidfile was given, check if there is a running process with that pid
if [ -n "$pidfile" ] ; then
  nproc=`find $pidfile* 2>/dev/null | wc -l`

  if [ "$nproc" -gt 1 ] ; then
	  echo "There seem to be too many ApMon processes running. Killing them all."
	  KillAllApMon
	  nproc=0;
  fi

  if [ -n "$force" ] ; then
	  echo "Requested killing previous ApMon instances."
	  KillAllApMon
  else
	  [[ "$nproc" -gt 0 ]] && exit 0;
  fi
fi

[ -n "$justKill" ] && exit 0

MONALISA_HOST=${MONALISA_HOST:-"localhost"}
APMON_DEBUG_LEVEL=${APMON_DEBUG_LEVEL:-"WARNING"}
destination=${APMON_CONFIG:-"['$MONALISA_HOST']"}

nodename4space="$SE_NAME""_server_xrootd_Services"
port="$XRDSERVERPORT"
if [ "x$host" = "x$MANAGERHOST" ] ; then
  nodename4space="$SE_NAME""_manager_xrootd_Services"
  port="$XRDMANAGERPORT"
fi

## get xrd informations
xrdinfo=`echo -ne "query config version\nspaceinfo /\nexit\n" |/usr/bin/xrdfs 127.0.0.1:$port`

## xrd version
xrdver=`echo "$xrdinfo" | grep ^v`

## get xrd space info; Reported size in bytes; convert to MiB with 2 decimals
totsp=`echo "$xrdinfo" | grep Total | awk -F: '{printf "%.2f\n",$2/1048576}'`
freesp=`echo "$xrdinfo" | grep Free | awk -F: '{printf "%.2f\n",$2/1048576}'`
lrgst=`echo "$xrdinfo" | grep Largest | awk -F: '{printf "%.2f\n",$2/1048576}'`

# export variables to be sure to be read by perl subprocess
export xrdver totsp freesp lrgst

#Finally, run the perl interpreter with a small program that sends all these parameters
exe="use strict;
use warnings;
use ApMon;
my \$apm = new ApMon(0);
\$apm->setLogLevel('$APMON_DEBUG_LEVEL');
\$apm->setDestinations($destination);
\$apm->setMonitorClusterNode('${hostGroup}_SysInfo', '$host');$srvMonCmds

my \$pid = fork();
if(\$pid == 0)
{
  while(1)
    {
		open (MYFILE, \">$pidfile.\$$\");
		print MYFILE \$\$;
		close (MYFILE);
		\$apm->sendBgMonitoring();
		print '$xrdver';
		\$apm->sendParameters('$nodename4space', '$host', 'xrootd_version', '$xrdver');
		\$apm->sendParameters('$nodename4space', '$host', 'space_total', '$totsp');
		\$apm->sendParameters('$nodename4space', '$host', 'space_free', '$freesp');
		\$apm->sendParameters('$nodename4space', '$host', 'space_largestfreechunk', '$lrgst');
		sleep(120);
    }
}
else
{
	my \$Line;
	my \$Var;
	my \$Val;
	my %Statsdata;
	open my \$Stdout, \"/usr/bin/mpxstats -f flat -p 1234 |\";
	while (<\$Stdout>)
    {
		undef %Statsdata;
		\$Line = \"\$_\";
		(\$Var,\$Val) = split(' ',\$Line);
		if(defined(\$Var))
      {
			\$Statsdata{\$Var} = \$Val;
      }
		\$apm->sendParameters('${hostGroup}_ApMon_Info', '$host', %Statsdata);
    }
}
"

#echo "Exe = [$exe]"
export PERL5LIB=/usr/share/perl5/:/usr/share/perl5/ApMon:${PERL5LIB}

## even if root, the logdir will be taken from the xrootd server cmd line
xrootd_server_line=`ps -eo pid,args= | grep 'bin/xrootd.*server\|bin/xrootd.*manager' | grep -v grep | head -1`

## if no xrootd server is running but servMon.sh is somehow used
if [ -z "$xrootd_server_line" ] ; then
  logfile="/tmp/servMon.log"
else
  xrootd_server_log=`awk '{for ( x = 1; x <= NF; x++ ) { if ($x == "-l") {print $(x+1)}   }}' <<< "$xrootd_server_line"`
  logdir=`dirname $xrootd_server_log`
  logfile="${logdir}/servMon.log"
fi

if [ -n "$pidfile" ] ; then
	# pid file given; run in background
	echo -e "`date` Starting ApMon in background mode...\nlogfile in: $logfile\npidfile in: $pidfile" | tee $logfile
	perl -e "$exe" </dev/null >> $logfile 2>&1 &
else
	# pid file not given; run in interactive mode
	echo -e "`date` Starting ApMon in interactive mode..."
	exec perl -e "$exe"
fi

