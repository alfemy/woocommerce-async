#!/usr/bin/env bash
echo "Listing files in /var/www/html/wp-content/..."
ls -l /var/www/html/wp-content/
echo "----------------------------------------"
echo "Listing files in /var/www/html/..."
ls -l /var/www/html/
echo "----------------------------------------"
echo "Listing files in /var/www/  ..."
ls -l /var/www/
echo "----------------------------------------"


cp -pr /var/www/html/wp-content  /var/www/ &
pid=$!
echo "Start copying wp-content files, PID is $pid"

while /bin/true; do
    sleep 1
    if ps -p $pid > /dev/null
    then
        echo "copying is running"
    else
        echo "copying is not running"
#        wait $pid
#        my_status=$?
#        echo "Exit code of copying is $my_status"
#        mv /var/www/html/wp-content{,_orgin} && echo "moved wp-content" || echo "failed to move wp-content"
        rm -rf /var/www/html/wp-content && echo "removed wp-content" || echo "failed to remove wp-content"
        ln -s /var/www/wp-content /var/www/html/wp-content && echo "linked wp-content" || echo "failed to link wp-content"
        echo "Copying is done"
        echo "Number or files in /var/www/html/wp-content:"
        find /var/www/html/wp-content | wc -l
        echo "Listing files in /var/www/html/wp-content/..."
        ls -l /var/www/html/wp-content/
        echo "----------------------------------------"
        echo "Number or files in /var/www/html:"
        find /var/www/html/ | wc -l
        echo "Listing files in /var/www/html/..."
        ls -l /var/www/html/
        echo "----------------------------------------"
        echo "Number or files in /var/www/:"
        find /var/www/ | wc -l
        echo "Listing files in /var/www/..."
        ls -l /var/www/
        echo "----------------------------------------"
        break
    fi
done &
