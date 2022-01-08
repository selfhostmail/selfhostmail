file { '/etc/wireguard':
  ensure => 'directory',
  mode   => '0600'
}
exec {'wireguard client enable':
  command => "/usr/bin/cp /root/`hostname -s`-wg0.conf /etc/wireguard/wg0.conf; sudo chmod 0700 /etc/wireguard/wg0.conf; /usr/bin/systemctl enable wg-quick@wg0; /usr/bin/systemctl start wg-quick@wg0; \
  /usr/bin/firewall-cmd --permanent --zone=trusted --add-interface=wg0; \
  /usr/bin/firewall-cmd --reload",
  unless  => "/usr/bin/systemctl is-enabled wg-quick@wg0"
}
