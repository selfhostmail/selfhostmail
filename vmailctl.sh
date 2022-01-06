#!/bin/bash
#set +o noglob
cd /tmp && rm -f /tmp/privatekey /tmp/publickey /tmp/presharedkey

usage() { echo -e "Usage: $0\n-c add|delete|changepw (required)\n-a 'alias@domain.example'\n-d 'domain.example'\n-u '<user>' (without domain!)" 1>&2; exit 1; }

function trim() {
    shopt -s extglob
    set -- "${1##+([[:space:]])}"
    printf "%s" "${1%%+([[:space:]])}" 
}

function check_user_exists() {
        mail=$1
        code=$(sudo -u postgres sh -c "psql -qtd postfix -c \"select id from virtual_users where email='$mail';\"")
        echo "${code}"
}

function check_domain_exists(){
        dom=$1
        code=$(sudo -u postgres sh -c "psql -qtd postfix -c \"select id from virtual_domains where virtual_domain='$dom';\"")
        echo "${code}"
}

function check_alias_exists(){
        mail=$1
        code=$(sudo -u postgres sh -c "psql -qtd postfix -c \"select id from virtual_aliases where source='$mail';\"")
        echo "${code}"
}

while getopts ":a:c:d:u:p:" o; do
        case "${o}" in
                a)      a=${OPTARG} ;;
                c)      c=${OPTARG}
                        [[ $c == 'adduser' || $c == 'deluser' || $c == 'changepw' || $c == 'addvdomain' || $c == 'delvdomain' || $c == 'addalias' || $c == 'delalias' ]] || usage
                        ;;
                d)      d=${OPTARG} ;;
                p)      p=${OPTARG} ;;
                u)      u=${OPTARG} ;;
                *)      usage       ;;
    esac
done
shift $((OPTIND-1))

echo "C: ${c}"

if [ -z "${c}" ] ; then
    usage
fi
echo "a = ${a}"
echo "d = ${u}"
echo "u = ${d}"
echo "p = ${p}"

if [[ $c == 'changepw' ]]; then
        if [ -z "${u}" ]; then
                usage
        fi
        if [ -z "${d}" ]; then
                usage
        fi
        email="${u}@${d}"
        if [ -z "${p}" ]; then
                echo -n Password:
                read -s password
        else
                $password = "${p}"
        fi

        enc_pw=`doveadm pw -s BLF-CRYPT -p "${password}"`
        enc_pw="${enc_pw//$/\\$}"
        cd /tmp
        userx=$(check_user_exists "${email}")
        if [[ $userx =~ '1' ]]; then
                   $(sudo -u postgres sh -c "psql -qd postfix -c \"update virtual_users set password='${enc_pw}' where email='${u}@${d}';\"")
        fi
elif [[ ${c} == 'adduser' ]]; then
        # check if domain and enforce help
        if [ -z "${u}" ]; then
                usage
        fi
        if [ -z "${d}" ]; then
                usage
        fi
        email="${u}@${d}"
        userx=$(check_user_exists "${email}")
        user_id=$(trim "${userx}")
        if ! [ -z $user_id ]; then
                echo "User ${u} already exists in ${d}, code ${user_id}!"
                exit 1
        fi
        domainx=$(check_domain_exists "${d}")
        domain_id=$(trim "${domainx}")
        if [ -z $domain_id ]; then
               echo "Domain ${d} does not exist!"
               exit 1
        fi
        if [ -z "${p}" ]; then
                echo -n Password:
                read -s password
        else
                $password = "${p}"
        fi
        enc_pw=`doveadm pw -s BLF-CRYPT -p "${password}"`
        echo "Adding ${email}..."
        `sudo -u postgres sh -c "psql -qd postfix -c \"insert into virtual_users (virtual_domain_id,email,password,maildir,quota) values ('${domain_id}','${email}','${enc_pw}','${u}/','500M')\""`
elif [[ $c == 'deluser' ]]; then
        if [ -z "${u}" ]; then
                usage
        fi
        if [ -z "${d}" ]; then
                usage
        fi
        email="${u}@${d}"
        userx=$(check_user_exists "${email}")
        if [[ ${userx} =~ '1' ]]; then
                `sudo -u postgres sh -c "psql -qd postfix -c \"delete from virtual_users where email='${u}@${d}'\""`
        else
                echo "User ${u} does not exist in domain ${d}"
                exit 1
        fi
elif [[ ${c} == 'addvdomain' ]]; then
        # check if domain and enforce help
        if [ -z "${d}" ]; then
                usage
        fi
        domainx=$(check_domain_exists "${d}")
        if [[ ${domain} =~ '1' ]]; then
                echo
                echo "Domain ${d} already exists!"
                exit 1
        fi
        `sudo -u postgres sh -c "psql -qd postfix -c \"insert into virtual_domains (virtual_domain,host,active) values ('${d}','${HOSTNAME}','true')\""`
elif [[ ${c} == 'delvdomain' ]]; then
        # check if domain and enforce help
        if [ -z "${d}" ]; then
                usage
        fi
        domainx=$(check_domain_exists "${d}")
        if ! [[ ${domainx} =~ '1' ]]; then
                echo
                echo "Domain ${d} does not exist - ${domainx}!"
                exit 1
        fi
        `sudo -u postgres sh -c "psql -qd postfix -c \"delete from virtual_domains where virtual_domain='${d}'\""`
elif [[ ${c} == 'addalias' ]]; then
        # check if domain and enforce help
        if [ -z "${a}" ]; then
                usage
        fi
        if [ -z "${d}" ]; then
                usage
        fi
        if [ -z "${u}" ]; then
                usage
        fi
        aliasx=$(check_alias_exists "${a}")
        domainx=$(check_domain_exists "${d}")
        userx=$(check_user_exists "${u}")
        if ! [[ $userx =~ '1' ]]; then
                echo "Userx ${u} does not exist ${userx}!"
                exit 1
        elif [[ ${aliasx} =~ '1' ]]; then
                echo "Alias ${a} exists already!"
                exit 1
        elif ! [[ ${domainx} =~ '1' ]]; then
                echo "Domain ${d} does not exist - ${domainx}!"
                exit 1
        fi
        aliasmail="${a}@${d}"
        `sudo -u postgres sh -c "psql -qd postfix -c \"insert into virtual_aliases (virtual_domain_id,source,destination) select id,'${aliasmail}','${u}' from virtual_domains where virtual_domain='${d}'\""`
fi
