file { '/etc/wireguard':
  ensure => 'directory',
  mode   => '0600'
}
exec {'wireguard client enable':
  command => "/usr/bin/cp /root/wg0.conf /etc/wireguard/wg0.conf; sudo chmod 0700 /etc/wireguard/wg0.conf; /usr/bin/systemctl enable wg-quick@wg0; /usr/bin/systemctl start wg-quick@wg0; \
  /usr/bin/firewall-cmd --permanent --zone=trusted --add-interface=wg0; \
  /usr/bin/firewall-cmd --reload",
  unless  => "/usr/bin/test -e /etc/wireguard/wg0.conf && /usr/bin/systemctl is-enabled wg-quick@wg0"
}
-> exec {"set resolv to dnsmasq":
  command => "/usr/bin/sed -i -E '0,/nameserver/{s/^(nameserver.*)/nameserver ${facts['wg_server_ip']}\\n\\1/}' /etc/resolv.conf",
  unless  => "/usr/bin/grep 'nameserver ${facts['wg_server_ip']}' /etc/resolv.conf"
}