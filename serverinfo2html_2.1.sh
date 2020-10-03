#!/bin/bash

# Script to get server information
# A script to produce an Server Info HTML file.
# Jean-Pierre.Pitout@mtn.co.za
# Additions made by LOB Linux Team

  VERSION="2.1"

# Build HTML header
htmlhead ()
{
   echo "<HTML>"
   echo "<HEAD>"
   echo "  <TITLE>"
   echo "Line-of-Business Linux - ServerInfo"
   echo "  </TITLE>"
   echo "</HEAD>"
   echo ""
   echo "<BODY>"
   echo "<h2> Server Info Script - Ver. $VERSION - Last Run `date +"%A %e %B,%Y at %T "` </h2>"
}

# Build HTML footer
htmlfoot ()
{
   echo "</BODY>"
   echo "</HTML>"
}

# check RHEL version

checkrhel()
{
   # for now, assume this script will run successfully on non red hat servers
   if [ ! -e /etc/redhat-release ]
   then
       return 0
   fi

   egrep -q "release 5|release 6|release 7" /etc/redhat-release

   if [ $? -ne 0 ]
   then
       echo "Sorry, this version of RHEL isn't supported"
       return 1
   fi
   return 0
}

# check if a command exists and is executable
checkcommand()
{
   cmdpath=`which $1 2>&1 > /dev/null`
   if [ $? -ne 0 ]
   then
       return 2
   fi
   if [ ! -x $cmdpath ]
   then
       return 3
   fi
}

# sanity check, do we have grep and other essentials, am I root?
sanity()
{
   if [ $EUID -ne 0 ]
   then
       echo "Need to run as root, exiting"
       exit 1
   fi

   # check that needed commands are available
   for cmd in sed cut grep bc wc hostname lspci
   do
       checkcommand $cmd || exit $?
   done
}

# CPU info
processor()
{
   echo " <h3>Processor</h3>"
   echo "<ul>"
   echo "<li> Processor Make: $(grep vendor_id /proc/cpuinfo | head -n 1 | cut -d : -f 2)</li>" | sed 's/\s\+/ /g' 
   echo "<li> Processor Model: $(grep "model name" /proc/cpuinfo | head -n 1 | cut -d : -f 2)</li>" | sed 's/\s\+/ /g'
   echo "<li> Processor Sockets: $(dmidecode | grep 'type 4,' | wc -l)</li>"
   echo "<li> Processor Cores: $(grep ^processor /proc/cpuinfo | wc -l)</li>"
   echo "</ul>"
}

# Memory info
memory()
{
   echo "<h3> Memory </h3>"
   MEMKB=$(grep MemTotal /proc/meminfo | cut -d : -f 2 | sed 's/\s*//' | cut -d ' ' -f 1)
   SWAPKB=$(free -k | grep -v ^- | grep ^Swap | sed 's/\s\+/ /g' | cut -d " " -f2)
   echo "<ul>"
   echo "<li> Memory: $(echo "scale=0; $MEMKB / 1000 " | bc) MB</li>"
   echo "<li> Swap: $(echo "scale=0; $SWAPKB / 1000 " | bc) MB</li>"
   echo "</ul>"
}

# network cards
network()
{
   echo "<h3> Network </h3>"
   # list interfaces and ip addresses
   checkcommand ip || return $?
   echo "<h4>IP addresses </h4>"
   # get list of interfaces
   INTERFACES=$(ip a | grep -e "^[0-9]" | cut -d ":" -f 2 | grep -v sit0 | grep -v lo | sed 's/\s//' | sort)
   # if we have bonding, display note about mac addresses
   echo $INTERFACES | grep -q bond 2> /dev/null
   if [ $? -eq 0 ]
   then
       echo "<p>Note: When using network bonding, hardware addresses for "
       echo "each interface in the bond may be the same as the bond device"
       echo "itself. This is usually the hardware address of the first network"
       echo "card.</p>"
       echo -n "<p>How to distinguish between bond types:</p>"
       echo -n "<p>1 MAC = 1 BOND_MAC then Active Backup/Adaptive</p>"
       echo -n "<p>x MAC = 1 BOND_MAC then Team/Balance/Round-Robin</p>"
   fi
   # html table
   echo "<table>"
   echo "<tr>"
   echo "<th>Interface</th>"
   echo "<th>IP Addresses</th>"
   echo "<th>Default Gateway</th>"
   echo "<th>HW Address</th>"
   echo "<th>Speed</th>"
   echo "<th>Driver </th>"
   echo "<th>Physical Device</th>"
   echo "</tr>"

   # We should probably change the entire way we handle building the rows for each interface since they may be
   # unconfigured, different types of bond or teamed. 
   # The best way would be to deal with them separately like the PowerPath devices in the Disk section.

   # loop through interfaces and get their info
   for INTERFACE in $INTERFACES
   do
       IPS=$(ip a ls dev $INTERFACE | grep inet | grep -v inet6 | sed 's/\s\+/ /g' | cut -d ' ' -f 3)
       GWADDR=$(route -n | grep $INTERFACE | grep "^0.0.0.0" | sed 's/\s\+/ /g' | cut -d ' ' -f2)
       HWADDR=$(ip a ls dev $INTERFACE | grep ether | sed 's/\s\+/ /g' | cut -d ' ' -f 3)
       SPEED=$(ethtool $INTERFACE 2> /dev/null | grep Speed | cut -d ":" -f 2)
       DRIVER=$(ethtool -i $INTERFACE 2> /dev/null | grep ^driver | cut -d " " -f 2)
       BUS=$(ethtool -i $INTERFACE 2> /dev/null | grep ^bus | cut -d " " -f 2 | cut -d ":" -f 2-)
       # only get physical device for physical interfaces
       PHYS=""
       if [ -n "$BUS" ]
       then
               PHYS=$(lspci | grep $BUS )
       fi
       if [ -z "$IPS" ]
       then
               IPS='Unconfigured_or_bond?'
       fi
       echo -n "<tr>"
       echo -n "<td>$INTERFACE </td>"

       # loop through IPs, in case we have more than one in our output
       FIRSTIP=1
       for IP in $IPS
       do
           # if this isn't the first ip we print, put a comma to seperate them
           if [ $FIRSTIP -ne 1 ]
           then
               echo -n ", "
           fi
           echo -n "<td>$IP</td>"
           FIRSTIP=0
       done
       echo -n "<td>$GWADDR</td>" | sed -e 's/\s\+/ /g'
       echo -n "<td>$HWADDR</td>" | sed -e 's/\s\+/ /g'
       echo -n "<td>$SPEED</td>" | sed -e 's/\s\+/ /g'
       echo -n "<td>$DRIVER</td>" | sed -e 's/\s\+/ /g'
       echo -n "<td>$PHYS</td>" | sed -e 's/\s\+/ /g'
       echo "</tr>"
   done
   echo "</table>"

   echo "<h4>Services (TCP)</h4>"
   # html table
   echo "<table>"
   echo "<tr>"
   echo "<th>Listening IP</th>"
   echo "<th>Port </th>"
   echo "<th>User </th>"
   echo "<th>Process ID </th>"
   echo "<th>Command</th>"
   echo "</tr>"

   # get PIDs of listening tcp process and loop through populating table
   #TCPSVCS=$(netstat -tple --numeric-hosts --numeric-ports | grep "^tcp" | sort -k7,7 -k4,4 | sed 's/\s\+/ /g' | cut -d ' ' -f9 | cut -d '/' -f1)
   TCPSVCS=$(netstat -tple --numeric-hosts --numeric-ports | grep "^tcp" | grep -v "127.0.0.1" | sort -k7,7 -k4,4 | sed 's/\s\+/ /g'| cut -d ' ' --output-delimiter="," -f4,7,9 | cut -d '/' -f1)

   for TCPSVC in $TCPSVCS
   do
     ADDRPORT=$(echo "$TCPSVC" | cut -d ',' -f1)
     PORT=$(echo "$ADDRPORT" | grep -o ":[0-9]\+$" | tr -d ":")
     ADDR=$(echo "$ADDRPORT" | sed "s/:$PORT//")
     PUSER=$(echo "$TCPSVC" | cut -d ',' -f2)
     PID=$(echo "$TCPSVC" | cut -d ',' -f3)
     PCMD=$(ps -p $PID -o cmd=)
     echo "<tr>"
     echo -n "<td>$ADDR</td>"
     echo -n "<td>$PORT</td>"
     echo -n "<td>$PUSER</td>"
     echo -n "<td>$PID</td>"
     echo -n "<td>$PCMD</td>"
     echo "</tr>"
   done
   echo "</table>"
   echo "<h4> Services (UDP)  </h4>"
   # html table
   echo "<table>"
   echo "<tr>"
   echo "<th> Listening IP </th>"
   echo "<th>Port </th>"
   echo "<th>User </th>"
   echo "<th>Process ID </th>"
   echo "<th>Command</th>"
   echo "</tr>"

   # get PIDs of listening udp process and loop through populating table
   UDPSVCS=$(netstat -uple --numeric-hosts --numeric-ports | grep "^udp" | grep -v "127.0.0.1" | sort -k6,6 -k4,4 | sed 's/\s\+/ /g'| cut -d ' ' --output-delimiter="," -f4,6,8 | cut -d '/' -f1)
   for UDPSVC in $UDPSVCS
   do
       ADDRPORT=$(echo "$UDPSVC" | cut -d ',' -f1)
       PORT=$(echo "$ADDRPORT" | grep -o ":[0-9]\+$" | tr -d ":")
       ADDR=$(echo "$ADDRPORT" | sed "s/:$PORT//")
       PUSER=$(echo "$UDPSVC" | cut -d ',' -f2)
       PID=$(echo "$UDPSVC" | cut -d ',' -f3)
       PCMD=$(ps -p $PID -o cmd=)
       echo "<tr>"
       echo -n "<td>$ADDR</td>"
       echo -n "<td>$PORT</td>"
       echo -n "<td>$PUSER</td>"
       echo -n "<td>$PID</td>"
       echo -n "<td>$PCMD</td>"
       echo "</tr>"
   done
   echo "</table>"
}

# Disk sizes
disk()
{
   echo "<h3> Filesystems </h3>"
   # physical disks
   echo "<h4> Disks </h4>"
   checkcommand fdisk || return $?
   # if we have powerpath, get list of disks to ignore
   POWERPATH=0
   checkcommand powermt && POWERPATH=1
   if [ $POWERPATH -eq 1 ]
   then
       ignore=`powermt display dev=all 2> /dev/null | grep qla \
           | grep -v Owner \
           | sed 's/^\s*//' | sed 's/\s\s\s*/:/g' | cut -d ':' -f 2 \
           | awk '{ printf "/dev/%s\n",$0 }'`
       # and include powerpath devices themselves
       ignore=`echo $ignore; powermt display dev=all 2> /dev/null \
           | grep Pseudo \
           | cut -d = -f 2 | awk '{ printf "/dev/%s\n",$0 }'`
   fi

   # html table
   echo "<table>"
   echo "<tr>"
   echo "<th>Disk</th>"
   echo "<th>Size</th>"
   echo "<th>Description</th>"
   echo "</tr>"

   # get list of disks
   disks=`fdisk -l 2> /dev/null | grep "Disk /" | cut -d ' ' -f 2 \
       | sed 's/,//' | sed 's/://' | sort`
   # loop through them
   for disk in $disks
   do
       # should we ignore this disk?
       showit=1
       for i in $ignore
       do
           if [ $i == $disk ]
           then
               showit=0
           fi
       done
       if [ $showit -eq 1 ]
       then
           echo "<tr>"
           echo "<td>"
           fdisk -l $disk 2> /dev/null | grep "Disk /" | grep -v identifier | cut -d ' ' -f 2,3,4 \
               | sed 's/,//' | sed 's/:/<\/td><td>/' | sed 's/$/ <\/td>/'
           echo "</tr>"
        fi
   done

   # handle powerpath devices seperately
   if [ $POWERPATH -eq 1 ]
   then
       # get list of powerpath devices
       disks=`powermt display dev=all 2> /dev/null | grep Pseudo | cut -d = -f 2 | sort`
       for disk in $disks
       do
           disksize=`fdisk -l /dev/$disk 2> /dev/null | grep Disk \
               | grep -v identifier | cut -d : -f 2 | cut -d ',' -f 1 | sed 's/^\s//'`
           description=`powermt display dev=$disk 2> /dev/null | grep Logical \
               | cut -d '[' -f 2 | sed 's/]//'`
           echo "<tr>"
           echo "<td> /dev/$disk</td><td> $disksize</td><td>$description</td>"
           echo "</tr>"
       done
   fi

   echo "</table>"
   # mounted filesystems
   echo "<h4> Mounted filesystems </h4>"
   # html table

   echo "<table>"
   echo "<tr>"
   echo "<th>Filesystem</th>"
   echo "<th>Type</th>"
   echo "<th>Size</th>"
   echo "<th>Used</th>"
   echo "<th>Avail</th>"
   echo "<th>% Used</th>"
   echo "<th>Mount point</th>"
   echo "</tr>"

   # get list of mounted filesystems
   mounted=$(df -P | egrep -v '^Filesystem|^tmpfs|^none|^udev'|awk '{print $1}')
   for fs in $mounted
   do
       # get df in the format we want it
       mountinfo=`df -hPT | grep $fs`
       fstype=`echo $mountinfo    | awk '{print $2 }'`
       fssize=`echo $mountinfo    | awk '{print $3 }' `
       fsused=`echo $mountinfo | awk '{print $4 }'`
       fsavail=`echo $mountinfo   | awk '{print $5 }'`
       fsusedper=`echo $mountinfo    | awk '{print $6 }'`
       fsmtpt=`echo $mountinfo    | awk '{print $7 }'`

       echo "<tr>"
       echo "<td> $fs </td><td> $fstype</td><td>$fssize</td><td>$fsused</td><td> $fsavail</td><td>$fsusedper</td><td>$fsmtpt</td>"
      echo "</tr>"
done

echo "</table>"
   # LVM
   checkcommand pvs || return 3
   checkcommand vgs || return 3
   checkcommand lvs || return 3
   echo "<h4> LVM </h4>"
   echo "<h5>Physical Volumes</h5>"

   # html table
   echo "<table>"
   echo "<tr>"
   echo "<th>Physical Volume</th>"
   echo "<th>Metadata Type</th>"
   echo "<th>Underlying Device Size</th>"
   echo "<th>PV Size</th>"
   echo "<th>PV Used</th>"
   echo "<th>PV Free</th>"
   echo "<th>Total Extents</th>"
   echo "<th>Allocated Extents</th>"
   echo "<th>Attributes</th>"
   echo "<th>Volume Group</th>"
   echo "</tr>"

   # get list of physical volumes, loop through them and display their information
   PVS=$(pvs --noheadings -o pv_name | sed 's/\s*//')
   for PV in $PVS
   do
       echo "<tr>"
       echo "<td>$(pvs --noheadings --separator "</td><td>" -o pv_name,pv_fmt,dev_size,pv_size,pv_used,pv_free,pv_pe_count,pv_pe_alloc_count,pv_attr,vg_name -O vg_name,pv_name $PV | sed 's/\s*//' | sed 's/$/<\/td>/')"
   echo "</tr>"
done
echo "</table>"
   # get list of volume groups, loop through them and display their information
   VGS=$(vgs --noheadings -o vg_name | sed 's/\s*//')
   for VG in $VGS
   do
       echo "<h5>Volume Group: $VG</h5>"
   
# html table
   echo "<table>"
   echo "<tr>"
   echo "<th>Volume Group </th>"
   echo "<th>Metadata Type </th>"
   echo "<th>VG Size </th>"
   echo "<th>VG Free</th>"
      echo "<th>Extent Size </th>"
      echo "<th>Total Extents </th>"
      echo "<th>Free Extents </th>"
      echo "<th>Phys Vols </th>"
      echo "<th>Max Phys Vols </th>"
      echo "<th>Log Vols </th>"
      echo "<th>Max Log Vols </th>"
      echo "<th>Snapshots </th>"
      echo "<th>Attributes</th>"
      echo "</tr>"
      echo "$(vgs --noheadings --separator "</td><td>" -o vg_name,vg_fmt,vg_size,vg_free,vg_extent_size,vg_extent_count,vg_free_count,pv_count,max_pv,lv_count,max_lv,snap_count,vg_attr -O vg_name $VG | sed 's/\s*//' | sed 's/^/<tr><td>/g'| sed 's/$/<\/td><\/tr>/g')"
      echo "</table>"

   # html table
   echo "<table>"
   echo "<tr>"
   echo "<th>Logical Volume</th>"
   echo "<th>LV Size</th>"
   echo "<th>LV Segments </th>"
   echo "<th>Attributes</th>"
   echo "<th>Snapshot Origin</th>"
   echo "<th>Snapshot Used %</th>"
   echo "</tr>"

   echo "<tr>"
#   echo "<td>$(lvs --noheadings --separator "</td><td>" -o lv_name,lv_size,seg_count,lv_attr,origin,snap_percent -O lv_name $VG | sed 's/\s*/ /' | sed 's/$/\n|-/'| sed 's/$/<\/td>/')"
   echo "$(lvs --noheadings --separator "</td><td>" -o lv_name,lv_size,seg_count,lv_attr,origin,snap_percent -O lv_name $VG | sed 's/\s*//' | sed 's/^/<tr><td>/g'| sed 's/$/<\/td><\/tr>/g')"
echo "</table>"
done
}

# Hardware manufacturer
hardware()
{
   echo "<h3> Hardware </h3>"
   checkcommand dmidecode || return $?
   checkrhel || return $?
   echo "<ul>"
      echo "<li> Manufacturer: $(dmidecode -s system-manufacturer)</li>"
   echo "<li>Model: $(dmidecode -s system-version)</li>"
   echo "<li>Product: $(dmidecode -s system-product-name)</li>"
   echo "<li>Serial Number: $(dmidecode -s system-serial-number)</li>"
   echo "<li>BIOS Version: $(dmidecode -s bios-version)</li>"
   echo "<li>BIOS Date: $(dmidecode -s bios-release-date)</li>"
   echo "</ul>"
}

# Chassis manufacturer
#chassis()
#{
#   echo "<h3> Chassis </h3>"
#   checkcommand dmidecode || return $?
#   checkrhel || return $?
#   echo "<ul>"
#   echo "<li>Manufacturer: $(dmidecode -s chassis-manufacturer)</li>"
#   echo "<li>Model: $(dmidecode -s chassis-version)</li>"
#   echo "<li>Serial number: $(dmidecode -s chassis-serial-number)</li>"
#   echo "<li>Asset tag: $(dmidecode -s chassis-asset-tag)</li>"
#   echo "</ul>"
#}

# users and groups
usergroups ()
{
echo "<h3> Users and Groups </h3>"
   # users
   echo "<h4> Local Users </h4>"
   # html table
   echo "<table>"
   echo "<tr>"
   echo "<th>Username</th>"
   echo "<th>UID</th>"
   echo "<th>Member Of</th>"
   echo "</tr>"

   # get list of users with uid above 500
   users=`awk -F: '$3 >= 500 {print $1}' /etc/passwd` 
   for user in $users 
   do
      uid=`id -u $user`
      memberof=`id -Gn $user`
      echo "<tr>"
      echo "<td>$user</td><td>$uid</td><td>$memberof</td> "
      echo "</tr>"
      echo "</tr>"
   done
   echo "</table>"
   echo "<h4> Local Groups </h4>"
   # html table
   echo "<table>"
   echo "<tr>"
   echo "<th>Group</th>"
   echo "<th>GID</th>"
   echo "</tr>"
   awk -F: '$3 >= 500 {print "<tr><td>"$1"</td><td>"$3"</td></tr>"}' /etc/group
   echo "</table>"
}

# operating system
operatingsystem()
{
   echo "<h3> Operating System </h3>"
   echo "<ul>"
   echo "<li>Hostname: $(hostname)</li>"
   if [ -f /etc/redhat-release ]
   then
       echo "<li>Version: $(cat /etc/redhat-release)</li>"
   fi
   checkcommand uname || return $?
   echo "<li>Kernel: $(uname -r)</li>"
   echo "<li>Architecture: $(uname -i)</li>"
   if [ -f /root/install.log ]
   then
       echo "<li>Installed: $(stat -c %y /root/install.log | cut -d " " -f 1)"
   fi
   echo "</ul>"
}

# Virtual machines
virtualmachines()
{
   checkcommand hostname || return 1
   HOSTNAME=`hostname`
   echo "<h3> Hypervisor (if available) </h3>"
  echo "FIXME - use dmidecode?/virt-who/vmware-tools? to get hyperviser information"
}

htmlhead
# sanity check
sanity
operatingsystem
processor
memory
#chassis
hardware
usergroups
#virtualmachines
disk
network
htmlfoot
