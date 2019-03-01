#!/bin/bash -e

system_user=ubuntu
nginx_user=www-data
app_archive=/magento.tar.gz

# Set an initial value

function exportParams() {
    dbhost=`grep 'MySQLEndPointAddress' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    dbuser=`grep 'DBMasterUsername' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    dbpassword=`grep 'DBMasterUserPassword' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    dbname=`grep 'DBName' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    cname=`grep 'DNSName' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    adminfirst=`grep 'AdminFirstName' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    adminlast=`grep 'AdminLastName' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    adminemail=`grep 'AdminEmail' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    adminuser=`grep 'AdminUserName' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    adminpassword=`grep 'AdminPassword' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    magentourl=`grep 'MagentoReleaseMedia' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    magentolanguage=`grep 'MagentoLanguage' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    magentocurrency=`grep 'MagentoCurrency' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    magentotimezone=`grep 'MagentoTimezone' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
}

if [ $# -ne 1 ]; then
    echo $0: usage: install_magento.sh "<param-file-path>"
    exit 1
fi

PARAMS_FILE=$1

echo dbhost
echo dbuser
echo dbname

dbhost='NONE'
dbuser='NONE'
dbpassword='NONE'
dbname='NONE'
cname='NONE'
adminfirst='NONE'
adminlast='NONE'
adminemail='NONE'
adminuser='NONE'
adminpassword='NONE'
magentourl='NONE'
magentolanguage='NONE'
magentocurrency='NONE'
magentotimezone='NONE'

#install_magento.sh dbhost dbuser dbpassword dbname cname adminfirstname adminlastname adminemail adminuser adminpassword cachehost efsid magentourl certificateid magentolanguage magentocurrency magentotimezone

if [ -f ${PARAMS_FILE} ]; then
    echo "Extracting parameter values from params file"
    exportParams
else
    echo "Parameters file not found or inaccessible."
    exit 1
fi

# cname = public name of the service (magento.javieros.tk)


EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
EC2_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed -e 's:\([0-9][0-9]*\)[a-z]*\$:\\1:'`"

sudo apt -y install \
    nginx \
    php7.2-fpm \
    php7.2-cli \
    php7.2-common \
    php7.2-curl \
    php7.2-gd \
    php7.2-iconv \
    php7.2-intl \
    php7.2-mbstring \
    php7.2-mysql \
    php7.2-soap \
    php7.2-xsl \
    php7.2-zip \
    acl

nginx -t

# Create self signed certificate
touch sslkey.conf
cat << EOF > sslkey.conf
[req]
prompt = no
distinguished_name = req_distinguished_name

[req_distinguished_name]
C = GB
emailAddress = developers@kingfisherdirect.co.uk
EOF


openssl req -x509 -nodes -days 365 -config sslkey.conf -newkey rsa:2048 -keyout /etc/ssl/certs/magento.key -out /etc/ssl/certs/magento.crt
rm ./sslkey.conf

# edit /etc/php/7.2/fpm/php.ini
# and /etc/php/7.2/cli/php.ini
# to set
#   memory_limit = 2G
#   max_execution_time = 1800
#   zlib.output_compression = On
# using sed command

systemctl restart php7.2-fpm

mkdir -p /var/www/html
setfacl -dR -m "u:$nginx_user:rwX" -m "u:$system_user:rwX" /var/www/html
setfacl -R -m "u:$nginx_user:rwX" -m "u:$system_user:rwX" /var/www/html

cat << 'EOF' > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
upstream fastcgi_backend {
        server unix:/tmp/php-cgi.socket;
        server 127.0.0.1:9000 backup;
}
server {
        set $MAGE_ROOT /var/www/html;
        include /etc/nginx/mime.types;
        listen 443 ssl default_server;
        server_name www.example.com;
        root $MAGE_ROOT/pub/;

        ssl_certificate /etc/ssl/certs/magento.crt;
        ssl_certificate_key /etc/ssl/certs/magento.key;
        
        index index.php;
        autoindex off;
        charset UTF-8;
        error_page 404 403 = /errors/404.php;
        # PHP entry point for setup application
        location ~* ^/setup($|/) {
            root $MAGE_ROOT;
            location ~ ^/setup/index.php {
                fastcgi_pass   fastcgi_backend;
                fastcgi_index  index.php;
                fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
                include        fastcgi_params;
            }

            location ~ ^/setup/(?!pub/). {
                deny all;
            }

            location ~ ^/setup/pub/ {
                add_header X-Frame-Options "SAMEORIGIN";
            }
        }

        # PHP entry point for update application
        location ~* ^/update($|/) {
            root $MAGE_ROOT;

            location ~ ^/update/index.php {
                fastcgi_split_path_info ^(/update/index.php)(/.+)$;
                fastcgi_pass   fastcgi_backend;
                fastcgi_index  index.php;
                fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
                fastcgi_param  PATH_INFO        $fastcgi_path_info;
                include        fastcgi_params;
            }

            # Deny everything but index.php
            location ~ ^/update/(?!pub/). {
                deny all;
            }

            location ~ ^/update/pub/ {
                add_header X-Frame-Options "SAMEORIGIN";
            }
        }

        location / {
            try_files $uri $uri/ /index.php?$args;
        }

        location /pub/ {
            location ~ ^/pub/media/(downloadable|customer|import|theme_customization/.*\.xml) {
                deny all;
            }
            alias $MAGE_ROOT/pub/;
            add_header X-Frame-Options "SAMEORIGIN";
        }

        location /static/ {
            # Uncomment the following line in production mode
            expires max;

            # Remove signature of the static files that is used to overcome the browser cache
            location ~ ^/static/version {
                rewrite ^/static/(version\d*/)?(.*)$ /static/$2 last;
            }

            location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2)$ {
                add_header Cache-Control "public";
                add_header X-Frame-Options "SAMEORIGIN";
                expires 1y;

                if (!-f $request_filename) {
                    rewrite ^/static/(version\d*/)?(.*)$ /static.php?resource=$2 last;
                }
            }
            location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
                add_header Cache-Control "no-store";
                add_header X-Frame-Options "SAMEORIGIN";
                expires    off;

                if (!-f $request_filename) {
                   rewrite ^/static/(version\d*/)?(.*)$ /static.php?resource=$2 last;
                }
            }
            if (!-f $request_filename) {
                rewrite ^/static/(version\d*/)?(.*)$ /static.php?resource=$2 last;
            }
            add_header X-Frame-Options "SAMEORIGIN";
        }

        location /media/ {
            try_files $uri $uri/ /get.php?$args;

            location ~ ^/media/theme_customization/.*\.xml {
                deny all;
            }

            location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2)$ {
                add_header Cache-Control "public";
                add_header X-Frame-Options "SAMEORIGIN";
                expires 1y;
                try_files $uri $uri/ /get.php?$args;
            }
            location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
                add_header Cache-Control "no-store";
                add_header X-Frame-Options "SAMEORIGIN";
                expires    off;
                try_files $uri $uri/ /get.php?$args;
            }
            add_header X-Frame-Options "SAMEORIGIN";
        }

        location /media/customer/ {
            deny all;
        }

        location /media/downloadable/ {
            deny all;
        }

        location /media/import/ {
            deny all;
        }

        # PHP entry point for main application
        location ~ (index|get|static|report|404|503)\.php$ {
            try_files $uri =404;
            fastcgi_pass   fastcgi_backend;
            fastcgi_buffers 1024 4k;

            fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
            fastcgi_param  PHP_VALUE "memory_limit=768M \n max_execution_time=600";
            fastcgi_read_timeout 600s;
            fastcgi_connect_timeout 600s;

            fastcgi_index  index.php;
            fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
            include        fastcgi_params;
        }
}
}
EOF

# mkdir -p /var/www/html
# chown ec2-user:nginx /var/www/html
# chmod g+w /var/www/html/
# usermod -g nginx ec2-user
# chgrp -R nginx /var/lib/php/7.2/*
# service nginx start

chmod a+x configure_magento.sh
mv configure_magento.sh /tmp

./tmp/configure_magento.sh $dbhost $dbuser $dbpassword $dbname $cname $adminfirst $adminlast $adminemail $adminuser $adminpassword $magentourl $magentolanguage $magentocurrency $magentotimezone

tar czf /root/media.tgz -C /var/www/html/pub/media .
# mount -t nfs4 -o vers=4.1 $efsid.efs.$EC2_REGION.amazonaws.com:/ /var/www/html/pub/media
rm -rf /var/www/html/pub/media/*
tar xzf /root/media.tgz -C /var/www/html/pub/media

# Remove passwords from files
sed -i s/${dbpassword}/xxxxx/g /var/log/cloud-init.log
sed -i s/${adminpassword}/xxxxx/g /var/log/cloud-init.log

# Remove params file used in bootstrapping
rm -f ${PARAMS_FILE}

cat << EOF > magento.cron
* * * * * /usr/bin/php -c /etc/php/7.2/php.ini /var/www/html/bin/magento cron:run | grep -v "Ran jobs by schedule" >> /var/www/html/var/log/magento.cron.log
* * * * * /usr/bin/php -c /etc/php/7.2/php.ini /var/www/html/update/cron.php >> /var/www/html/var/log/update.cron.log
* * * * * /usr/bin/php -c /etc/php/7.2/php.ini /var/www/html/bin/magento setup:cron:run >> /var/www/html/var/log/setup.cron.log
EOF

crontab -u ubuntu magento.cron



