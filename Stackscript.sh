#!/bin/bash
# 
#<UDF name="hostname" label="The hostname for the new Linode.">
HOSTNAME=Deng
#<UDF name="fqdn" label="The new Linode's Fully Qualified Domain Name">
FQDN=deng.io 
#<UDF name="USER" label="Unprivileged User Account" />
USER=Wade
#<UDF name="USER_PASSWORD" label="Unprivileged User Password" />
USER_PASSWORD=
#


set -e

function system_set_timezone {
    echo "tzdata tzdata/Areas select Europe" | debconf-set-selections
    echo "tzdata tzdata/Zones/Europe select London" | debconf-set-selections
    TIMEZONE="Europe/London"
    echo $TIMEZONE > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata
}

function system_setup_iptables {
    cat > /etc/iptables.firewall.rules << EOF
*filter

#  Allow all loopback (lo0) traffic and drop all traffic to 127/8 that doesn't use lo0
-A INPUT -i lo -j ACCEPT
#-A INPUT ! -i lo -d 127.0.0.0/8 -j REJECT

#  Accept all established inbound connections
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

#  Allow all outbound traffic - you can modify this to only allow certain traffic
-A OUTPUT -j ACCEPT

#  Allow HTTP and HTTPS connections from anywhere (the normal ports for websites and SSL).
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT

#  Allow ports for MONGODB
#-A INPUT -p tcp --dport 27017 -j ACCEPT

#  Allow ports for nodejs
#-A INPUT -p tcp --dport 3000 -j ACCEPT

#  Allow ports for livereload
#-A INPUT -p tcp --dport 35729 -j ACCEPT

#  Allow SSH connections
#  The -dport number should be the same port number you set in sshd_config
-A INPUT -p tcp -m state --state NEW --dport 2208 -j ACCEPT

#  Allow ping
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT

#  Log iptables denied calls
-A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables denied: " --log-level 7

#  Reject all other inbound - default deny unless explicitly allowed policy
-A INPUT -j REJECT
-A FORWARD -j REJECT

COMMIT
EOF
    cat > /etc/network/if-pre-up.d/firewall << EOF
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.firewall.rules
EOF
    iptables-restore < /etc/iptables.firewall.rules
    sudo chmod +x /etc/network/if-pre-up.d/firewall
    
    cat > /etc/fireoff.sh << EOF        
#!/bin/bash
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT      
EOF
    sudo chmod +x /etc/fireoff.sh       
}

function install_nginx {
apt-get -y install nginx
echo "  upstream app_$FQDN {" > "/etc/nginx/sites-available/$FQDN"
echo "          server 127.0.0.1:3000;" >> "/etc/nginx/sites-available/$FQDN"
echo "  }" >> "/etc/nginx/sites-available/$FQDN"
echo "  server {" >> "/etc/nginx/sites-available/$FQDN"
echo "          listen 0.0.0.0:80;" >> "/etc/nginx/sites-available/$FQDN"
echo "          server_name www.$FQDN $FQDN;" >> "/etc/nginx/sites-available/$FQDN"
echo "          access_log /var/log/nginx/$FQDN.access.log;" >> "/etc/nginx/sites-available/$FQDN"
echo "          error_log /var/log/nginx/$FQDN.error.log debug;" >> "/etc/nginx/sites-available/$FQDN"
echo "          location / {" >> "/etc/nginx/sites-available/$FQDN"
echo '            proxy_set_header X-Real-IP $remote_addr;' >> "/etc/nginx/sites-available/$FQDN"
echo '            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' >> "/etc/nginx/sites-available/$FQDN"
echo '            proxy_set_header Host $http_host;' >> "/etc/nginx/sites-available/$FQDN"
echo '            proxy_set_header X-NginX-Proxy true;' >> "/etc/nginx/sites-available/$FQDN"
echo "            proxy_pass http://app_$FQDN/;" >> "/etc/nginx/sites-available/$FQDN"
echo "            proxy_redirect off;" >> "/etc/nginx/sites-available/$FQDN"
echo "          }" >> "/etc/nginx/sites-available/$FQDN"
echo "  }" >> "/etc/nginx/sites-available/$FQDN"
ln -s "/etc/nginx/sites-available/$FQDN" "/etc/nginx/sites-enabled/$FQDN"
/etc/init.d/nginx restart
}

function configure_users {
    #deluser irc #delete irc user
    #deluser games #delete games user
    #deluser news #delete nntp daemon user
    #deluser uucp #delete uucp user
    #deluser proxy #delete proxy user
    #deluser list #delete mailing list user
    #deluser gnats #delete gnats bug reporting user
    useradd -m -s /bin/bash $USER #add user account 
    echo "$USER:$USER_PASSWORD" | chpasswd #setpassword
    echo "$USER ALL=(ALL) ALL" >> /etc/sudoers # add user to sudoers
    sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/g' /home/$USER/.bashrc
    # passwd -l root # lock out root
}

function install_git_mongo {
    # Install git
    apt-get -y install git
    # install mongodb
    apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10
    echo 'deb http://downloads-distro.mongodb.org/repo/debian-sysvinit dist 10gen' | sudo tee /etc/apt/sources.list.d/mongodb.list
    apt-get update
    apt-get install -y mongodb-org
    service mongod start
}

function install_node_npm {
    curl https://gist.githubusercontent.com/isaacs/579814/raw/ba4228867d7578b8a0c66184f9f5df494f70ad15/node-and-npm-in-30-seconds.sh >/home/$USER/install_node.sh
    cd /home/$USER/
    chown $USER:$USER install_node.sh
    chmod +x install_node.sh
    su $USER -c "./install_node.sh"
}
  
function system_setup {  
    # This sets the variable $IPADDR to the IP address the new Linode receives. 
    IPADDR=$(/sbin/ifconfig eth0 | awk '/inet / { print $2 }' | sed 's/addr://')

    # This section sets the hostname. 
    echo $HOSTNAME > /etc/hostname 
    hostname -F /etc/hostname
          
    # This section sets the Fully Qualified Domain Name (FQDN) in the hosts file. 
    echo $IPADDR $FQDN $HOSTNAME >> /etc/hosts

    # This updates the packages on the system from the distribution repositories.
    apt-get remove apt-listchanges
    apt-get update 
    apt-get upgrade -y
    
    # Enable system build tools
    apt-get -q -y install build-essential
    
    # Sort out SSH
    echo "KeepAlive yes" >> /etc/ssh/sshd_config
    echo "ClientAliveInterval 120" >> /etc/ssh/sshd_config
    echo "ClientAliveCountMax 5" >> /etc/ssh/sshd_config
    /etc/init.d/ssh restart     
}

# Get down to business
system_setup
system_set_timezone
system_setup_iptables
configure_users
install_git_mongo
install_nginx
install_node_npm
