#!/bin/bash

# === Begin user editable fields ===
# All variables can be set via the environment or edited here. 
# Generate a new encryption key with 'consul keygen'

# Example: 
# CONSUL_JOIN_HOSTS='"192.168.1.100", "192.168.1.101", "192.168.1.102"'
[[ -n $CONSUL_JOIN_HOSTS ]] ||  CONSUL_JOIN_HOSTS=''
[[ -n $ENCRYPT_KEY       ]] ||  ENCRYPT_KEY=''
[[ -n $DATACENTER        ]] ||  DATACENTER=''
[[ -n $CONSUL_BINS       ]] ||  CONSUL_BINS='https://releases.hashicorp.com/consul/0.6.3/consul_0.6.3_linux_amd64.zip'
[[ -n $CONSUL_WEBUI      ]] ||  CONSUL_WEBUI='https://releases.hashicorp.com/consul/0.6.3/consul_0.6.3_web_ui.zip'
[[ -n $CONSUL_IPBIND     ]] ||  CONSUL_IPBIND=$(ifconfig | grep "inet " | grep -v '127.0.0.1' | head -1 | awk -F'[: ]+' '{ print $4 }')

# === End user editable fields ===

# Install dependencies
yum -y install unzip wget || apt-get --assume-yes install unzip wget

# Download and extract consul and webui components
cd /tmp/
[[ -f /tmp/consul.zip ]] || wget -q $CONSUL_BINS -O /tmp/consul.zip
[[ -f /tmp/consul-webui.zip ]] || wget -q $CONSUL_WEBUI -O /tmp/consul-webui.zip
cd /tmp
unzip -o consul.zip
chmod +x consul
mkdir /opt/consul
mv dist /opt/consul
mv consul /usr/bin/consul
unzip -o consul-webui.zip -d /opt/consul/dist

# Manage permissions
useradd consul --system
mkdir -p /etc/consul.d/bootstrap /etc/consul.d/client /etc/consul.d/server
chown -R root:consul /etc/consul.d
chown -R consul:consul /opt/consul
chmod -R 750 /opt/consul
chmod -R 750 /etc/consul.d

# Firewall rules, only for server, test the rules after bootstrap to make sure theres not a reject rule preceding these
iptables -N consul_ports
iptables -I INPUT 2 -j consul_ports
iptables -A consul_ports -p tcp -m state --state NEW -m tcp --dport 8300 -j ACCEPT
iptables -A consul_ports -p tcp -m state --state NEW -m tcp --dport 8301 -j ACCEPT
iptables -A consul_ports -p tcp -m state --state NEW -m tcp --dport 8302 -j ACCEPT
iptables -A consul_ports -p tcp -m state --state NEW -m tcp --dport 8400 -j ACCEPT
iptables -A consul_ports -p tcp -m state --state NEW -m tcp --dport 8500 -j ACCEPT
iptables -A consul_ports -p tcp -m state --state NEW -m tcp --dport 8600 -j ACCEPT

service iptables save
service iptables reload

# Create config files
cat > /etc/init.d/consul <<EOL
#!/bin/sh
#
# consul        Start the consul daemon
#
# chkconfig: 345 99 10
# description: Starts the Consul daemon
#
# processname: consul

# Source function library.
. /etc/rc.d/init.d/functions

RETVAL=0

# Default variables
CONSUL_BIN="/usr/bin/consul"
CONSUL_CONF="/etc/consul.d"
CONSUL_USER="consul"
PIDFILE="/var/run/consul.pid"
LOGFILE="/var/log/consul.log"
GOMAXPROCS=2 # When Consul is built with Go 1.5, remove this

# See how we were called.
case "\$1" in
  start)
        echo -n "Starting Consul daemon: "
        
        # Disable hugepages
        # https://bugzilla.redhat.com/show_bug.cgi?id=879801
        echo never > /sys/kernel/mm/transparent_hugepage/enabled
        echo never > /sys/kernel/mm/transparent_hugepage/defrag
        
        # Verify the log file end pid file xists and the user can write to it
        touch \$LOGFILE \$PIDFILE
        chown root:\$CONSUL_USER \$LOGFILE
        chmod 660 \$LOGFILE
        chown root:\$CONSUL_USER \$PIDFILE
        chmod 660 \$PIDFILE

        daemon --check consul --user \$CONSUL_USER --pidfile=\$PIDFILE "\$CONSUL_BIN agent -config-dir=\$CONSUL_CONF -pid-file=\$PIDFILE &>> \$LOGFILE &"
        echo
        ;;
  stop)
        echo -n "Stopping Consul daemon: "
        killproc -p \$PIDFILE consul
        echo
        ;;
  status)
        status -p \$PIDFILE \$CONSUL_BIN
        RETVAL=\$?
        ;;
  restart)
        \$0 stop
        \$0 start
        RETVAL=\$?
        ;;
  *)
        echo "Usage: consul {start|stop|status|restart}"
        exit 1
  esac

exit \$REVAL
EOL

cat > /etc/consul.d/bootstrap/consul.json <<EOL
{
  "datacenter": "$DATACENTER",
  "data_dir": "/opt/consul/data",
  "log_level": "INFO",
  "server": true,
  "ui_dir": "/opt/consul/dist",
  "bind_addr": "$CONSUL_IPBIND",
  "client_addr": "$CONSUL_IPBIND",
  "disable_remote_exec": true,
  "encrypt": "$ENCRYPT_KEY",
  "bootstrap_expect": 3
}
EOL

cat > /etc/consul.d/server/consul.json <<EOL
{
  "datacenter": "$DATACENTER",
  "data_dir": "/opt/consul/data",
  "log_level": "INFO",
  "server": true,
  "ui_dir": "/opt/consul/dist",
  "bind_addr": "$CONSUL_IPBIND",
  "client_addr": "$CONSUL_IPBIND",
  "disable_remote_exec": true,
  "encrypt": "$ENCRYPT_KEY",
  "start_join": [$CONSUL_JOIN_HOSTS]

}
EOL

cat > /etc/consul.d/client/consul.json <<EOL
{
  "datacenter": "$DATACENTER",
  "data_dir": "/opt/consul/data",
  "log_level": "INFO",
  "server": false,
  "disable_remote_exec": true,
  "leave_on_terminate": true,
  "encrypt": "$ENCRYPT_KEY",
  "start_join": [$CONSUL_JOIN_HOSTS]
}
EOL

cat > /etc/logrotate.d/consul <<EOL
/var/log/consul.log {
  daily
  rotate 8
  missingok
  compress
  copytruncate
  delaycompress
}
EOL

chmod +x /etc/init.d/consul
