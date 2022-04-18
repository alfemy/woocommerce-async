#!/usr/bin/env bash
echo "Running docker-entrypoint.sh"
echo "Wordpress version is 5.3.9"
set -Eeuo pipefail
if [[ "$1" == apache2* ]] || [ "$1" = 'php-fpm' ]; then
	uid="$(id -u)"
	gid="$(id -g)"
	if [ "$uid" = '0' ]; then
		case "$1" in
			apache2*)
				user="${APACHE_RUN_USER:-www-data}"
				group="${APACHE_RUN_GROUP:-www-data}"

				# strip off any '#' symbol ('#1000' is valid syntax for Apache)
				pound='#'
				user="${user#$pound}"
				group="${group#$pound}"
				;;
			*) # php-fpm
				user='www-data'
				group='www-data'
				;;
		esac
	else
		user="$uid"
		group="$gid"
	fi

	if [ ! -e index.php ] && [ ! -e wp-includes/version.php ]; then
		# if the directory exists and WordPress doesn't appear to be installed AND the permissions of it are root:root, let's chown it (likely a Docker-created directory)
		if [ "$uid" = '0' ] && [ "$(stat -c '%u:%g' .)" = '0:0' ]; then
			chown "$user:$group" .
		fi

		echo >&2 "WordPress not found in $PWD - copying now..."
		if [ -n "$(find -mindepth 1 -maxdepth 1 -not -name wp-content)" ]; then
			echo >&2 "WARNING: $PWD is not empty! (copying anyhow)"
		fi
		sourceTarArgs=(
			--create
			--file -
			--directory /usr/src/wordpress
			--owner "$user" --group "$group"
		)
		targetTarArgs=(
			--extract
			--file -
		)
		if [ "$uid" != '0' ]; then
			# avoid "tar: .: Cannot utime: Operation not permitted" and "tar: .: Cannot change mode to rwxr-xr-x: Operation not permitted"
			targetTarArgs+=( --no-overwrite-dir )
		fi
		# loop over "pluggable" content in the source, and if it already exists in the destination, skip it
		# https://github.com/docker-library/wordpress/issues/506 ("wp-content" persisted, "akismet" updated, WordPress container restarted/recreated, "akismet" downgraded)
		for contentPath in \
			/usr/src/wordpress/.htaccess \
			/usr/src/wordpress/wp-content/*/*/ \
		; do
			contentPath="${contentPath%/}"
			[ -e "$contentPath" ] || continue
			contentPath="${contentPath#/usr/src/wordpress/}" # "wp-content/plugins/akismet", etc.
			if [ -e "$PWD/$contentPath" ]; then
				echo >&2 "WARNING: '$PWD/$contentPath' exists! (not copying the WordPress version)"
				sourceTarArgs+=( --exclude "./$contentPath" )
			fi
		done
		tar "${sourceTarArgs[@]}" . | tar "${targetTarArgs[@]}"
		echo >&2 "Complete! WordPress has been successfully copied to $PWD"
	fi

	wpEnvs=( "${!WORDPRESS_@}" )
	if [ ! -s wp-config.php ] && [ "${#wpEnvs[@]}" -gt 0 ]; then
		for wpConfigDocker in \
			wp-config-docker.php \
			/usr/src/wordpress/wp-config-docker.php \
		; do
			if [ -s "$wpConfigDocker" ]; then
				echo >&2 "No 'wp-config.php' found in $PWD, but 'WORDPRESS_...' variables supplied; copying '$wpConfigDocker' (${wpEnvs[*]})"
				# using "awk" to replace all instances of "put your unique phrase here" with a properly unique string (for AUTH_KEY and friends to have safe defaults if they aren't specified with environment variables)
				awk '
					/put your unique phrase here/ {
						cmd = "head -c1m /dev/urandom | sha1sum | cut -d\\  -f1"
						cmd | getline str
						close(cmd)
						gsub("put your unique phrase here", str)
					}
					{ print }
				' "$wpConfigDocker" > wp-config.php
				if [ "$uid" = '0' ]; then
					# attempt to ensure that wp-config.php is owned by the run user
					# could be on a filesystem that doesn't allow chown (like some NFS setups)
					chown "$user:$group" wp-config.php || true
				fi
				break
			fi
		done
	fi
fi

mkdir -p /var/www/wp-content/
chown www-data:www-data  /var/www/wp-content

#Do not fail if the environment variables are not set
set +u
#Assign the WSP DB environment variables to the WORDPRESS_ENVIRONMENT variables
if ! [ -z "$DB_HOST" ]; then
  export WORDPRESS_DB_HOST="$DB_HOST"
fi
if ! [ -z "$DB_USER" ]; then
  export WORDPRESS_DB_USER="$DB_USER"
fi
if ! [ -z "$DB_NAME" ]; then
  export WORDPRESS_DB_NAME="$DB_NAME"
fi
if ! [ -z "$DB_PASSWORD" ]; then
  export WORDPRESS_DB_PASSWORD="$DB_PASSWORD"
fi

#Assign default values to the WORDPRESS_ENVIRONMENT variables if they are not set
if [ -z "$WORDPRESS_ADMIN_USER" ]; then
  export WORDPRESS_ADMIN_USER='admin'
fi
if [ -z "$WORDPRESS_ADMIN_EMAIL" ]; then
  export WORDPRESS_ADMIN_EMAIL='wsp@local.host'
fi
if [ -z "$WORDPRESS_TITLE" ]; then
  export WORDPRESS_TITLE='WSP AWS'
fi

#Show static page with error if $WORDPRESS_URL is not set
if [ -z "$WORDPRESS_URL" ]; then
  echo '<h1>Environment variable $WORDPRESS_URL is not set. Please set it with Wordpress domain and re-deploy</h1>' > /var/www/html/index.html
  echo "DirectoryIndex index.html" >> /var/www/html/.htaccess
  echo "Running Web-server to show error that WORDPRESS_URL is not set"
  exec "$@"
else
  echo "Removing DirectoryIndex directive from .htaccess, index.php will be served"
  sed -i '/DirectoryIndex/d' /var/www/html/.htaccess
fi

set +e
export WP_CLI_CACHE_DIR="/tmp/.wp-cli/cache/"

##Create a static page to pass health check and debug
#echo '<h1>Temporary page to pass AWS health check</h1>' > /var/www/html/index.html
#echo "DirectoryIndex index.html" >> /var/www/html/.htaccess
#echo "Running Web-server"
#exec "$@"

wp core --allow-root is-installed
INSTALLED=$?
set -e
if [ $INSTALLED -eq 0 ]; then
    echo "Wordpress is already installed"
    echo "Starting Apache"
    exec "$@"
else
    echo "Wordpress is not installed, going to install"
    if [ -z "$WORDPRESS_ADMIN_PASSWORD" ]; then
      runuser -u www-data -- wp core install --skip-email --title="$WORDPRESS_TITLE" \
       --url="$WORDPRESS_URL" --admin_user="$WORDPRESS_ADMIN_USER" \
       --admin_email="$WORDPRESS_ADMIN_EMAIL" --path=/var/www/html/
    else
      runuser -u www-data -- wp core install --skip-email --title="$WORDPRESS_TITLE" --url="$WORDPRESS_URL" \
      --admin_user="$WORDPRESS_ADMIN_USER" --admin_email="$WORDPRESS_ADMIN_EMAIL" \
      --admin_password="$WORDPRESS_ADMIN_PASSWORD" --path=/var/www/html/
    fi
    runuser -u www-data -- wp plugin activate woocommerce
    runuser -u www-data -- wp theme activate storefront
    runuser -u www-data -- wp --user=1 wc product create --name="Example of a simple product" --type="simple" --regular_price="11.00"
    runuser -u www-data -- wp --user=1 wc product create --name="Example of an variable product" --type="variable" --attributes='[ { "name":"size", "variation":"true", "options":"X|XL" } ]'
    runuser -u www-data -- wp --user=1 wc product_variation create 11 --attributes='[ { "name":"size", "option":"X" } ]' --regular_price="51.00"
    runuser -u www-data -- wp option update page_on_front 5
    runuser -u www-data -- wp option update show_on_front page
    echo "End configuring WordPress"
fi

set -u

#echo "Run copying wp-content in background"
#runuser -u www-data -- /async-copy.sh > /var/www/html/sync.log 2>&1
runuser -u www-data -- cp -pr /var/www/html/wp-content  /var/www/ &
pid=$!
echo "Start copying wp-content files, PID is $pid"

while /bin/true; do
    sleep 1
    if ps -p $pid > /dev/null
    then
        echo "copying is running"
    else
        echo "copying is not running"
        runuser -u www-data -- mv /var/www/html/wp-content /var/www/html/wp-content_origin && echo "moved wp-content" || echo "failed to move wp-content"
        runuser -u www-data -- ln -s /var/www/wp-content /var/www/html && echo "linked wp-content" || echo "failed to link wp-content"
        break
    fi
done &


echo "Starting Apache"
exec "$@"
}