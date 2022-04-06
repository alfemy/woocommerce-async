#!/usr/bin/env bash
cp -pr /var/www/html/wp-content  /var/www/ &

pid=$!
echo "Start rsync wordpress files, PID is $pid"

while /bin/true; do
    sleep 1
    if ps -p $pid > /dev/null
    then
        echo "rsync is running"
    else
        echo "rsync is not running"
#        runuser -u www-data -- rm -rf /var/www/html/wp-content

#        runuser -u www-data -- mv /var/www/html/wp-content{,_orgin}
#        runuser -u www-data -- ln -s /var/www/wp-content /var/www/html/wp-content

        mv /var/www/html/wp-content{,_orgin}
        ln -s /var/www/wp-content /var/www/html/wp-content
        break
    fi
done &