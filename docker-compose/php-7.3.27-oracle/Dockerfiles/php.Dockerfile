FROM php:7.3.27-fpm-alpine3.13
RUN mkdir -p /var/www/html
WORKDIR /var/www/html
#	custom.ini es el php.ini, se setea la configuración
ADD custom.php.ini /usr/local/etc/php/conf.d/custom.ini
RUN apk add openldap-back-mdb
RUN apk add --update --virtual .build-deps g++ make zlib-dev libidn2-dev libevent-dev icu-dev libidn-dev openldap libxml2-dev
RUN apk --update --no-cache add php7-ldap libldap php-ldap  openldap-clients openldap openldap-back-mdb
RUN apk add --update --no-cache \
	libzip-dev \
	curl-dev \
	libxml2-dev \
	libpng-dev \
	$PHPIZE_DEPS \
	libnsl \
	libaio \
	gcc \
	openssl-dev \
	autoconf \ 
	musl-dev \
	php7-openssl \
	libc6-compat \
	gcompat 

RUN docker-php-ext-configure gd

RUN docker-php-ext-install \
	curl \
	dom \
	gd \
	json \
	tokenizer \
	zip 

RUN pecl install redis && docker-php-ext-enable redis
#	inicio memcache
#	Instalación de extenciones PHP (igbinary y memcached)
RUN apk add --no-cache --update libmemcached-libs zlib
RUN set -xe && \
	cd /tmp/ && \
	apk add --no-cache --update --virtual .phpize-deps $PHPIZE_DEPS && \
	apk add --no-cache --update --virtual .memcached-deps zlib-dev libmemcached-dev cyrus-sasl-dev && \
#	Instalación igbinary (dependencias del memcached)
	pecl install igbinary && \
#	Instalación memcached
	( \
		pecl install --nobuild memcached && \
		cd "$(pecl config-get temp_dir)/memcached" && \
		phpize && \
		./configure --enable-memcached-igbinary && \
		make -j$(nproc) && \
		make install && \
		cd /tmp/ \
	) && \
#	Activar extenciones PHP
	docker-php-ext-enable igbinary memcached && \
	rm -rf /tmp/* && \
	apk del .memcached-deps .phpize-deps
#	Fin memcache

#	Soporte LDAP
ARG DOCKER_PHP_ENABLE_LDAP

RUN echo -n "With ldap support:          " ; if [[ "${DOCKER_PHP_ENABLE_LDAP}" = "on" ]] ;      then echo "Yes"; else echo "No" ; fi && \
	if [ -z ${DOCKER_USER_UID+x} ]; then echo "DOCKER_USER_UID is unset"; DOCKER_USER_UID=1000; else echo "DOCKER_USER_UID is set to '$DOCKER_USER_UID'"; fi && \
	if [ -z ${DOCKER_USER_GID+x} ]; then echo "DOCKER_USER_GID is unset"; DOCKER_USER_GID=1000; else echo "DOCKER_USER_GID is set to '$DOCKER_USER_GID'"; fi

#	Activar LDAP
ARG DOCKER_PHP_ENABLE_LDAP
RUN echo -n "With ldap support:          " ; if [[ "${DOCKER_PHP_ENABLE_LDAP}" = "on" ]] ;      then echo "Yes"; else echo "No" ; fi && \
	if [ -z ${DOCKER_USER_UID+x} ]; then echo "DOCKER_USER_UID is unset"; DOCKER_USER_UID=1000; else echo "DOCKER_USER_UID is set to '$DOCKER_USER_UID'"; fi && \
	if [ -z ${DOCKER_USER_GID+x} ]; then echo "DOCKER_USER_GID is unset"; DOCKER_USER_GID=1000; else echo "DOCKER_USER_GID is set to '$DOCKER_USER_GID'"; fi
RUN if [ "${DOCKER_PHP_ENABLE_LDAP}" != "off" ]; then \
	#	Dependencias para LDAP
	apk add --update --no-cache \
		libldap && \
	#	Construir dependencias para LDAP
	apk add --update --no-cache --virtual .docker-php-ldap-dependancies \
		openldap-dev && \
	docker-php-ext-configure ldap && \
	docker-php-ext-install ldap && \
	apk del .docker-php-ldap-dependancies && \
	php -m; \
	else \
	echo "Skip ldap support"; \
	fi
#	Fin soporte LDAP

RUN ln -s /usr/lib/libnsl.so.2 /usr/lib/libnsl.so.1 && \
	ln -s /usr/lib/libc.so /usr/lib/libresolv.so.2

#	Instalacion del cliente de Oracle
RUN mkdir /opt/oracle \
	&& cd /opt/oracle

ADD instantclient-basic-linux.x64-19.15.0.0.0dbru.zip /opt/oracle/instantclient-basic-linux.x64-19.15.0.0.0dbru.zip
ADD instantclient-sdk-linux.x64-19.15.0.0.0dbru.zip /opt/oracle/instantclient-sdk-linux.x64-19.15.0.0.0dbru.zip

# Copiar imagen oficial de Composer para PHP
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

RUN rm -rf /opt/oracle/instantclient_19_6/*

RUN unzip /opt/oracle/instantclient-basic-linux.x64-19.15.0.0.0dbru.zip -d /opt/oracle \
	&& unzip /opt/oracle/instantclient-sdk-linux.x64-19.15.0.0.0dbru.zip -d /opt/oracle \
	&& ln -sf /opt/oracle/instantclient_19_15/libclntsh.so.19.1 /opt/oracle/instantclient_19_15/libclntsh.so \
	&& ln -sf /opt/oracle/instantclient_19_15/libclntshcore.so.19.1 /opt/oracle/instantclient_19_15/libclntshcore.so \
	&& ln -sf /opt/oracle/instantclient_19_15/libocci.so.19.1 /opt/oracle/instantclient_19_15/libocci.so \
	&& rm -rf /opt/oracle/*.zip

# Instalación de las extenciones del cliente de Oracle
RUN docker-php-ext-configure pdo_oci --with-pdo-oci=instantclient,/opt/oracle/instantclient_19_15,19.1 \
	&& echo 'instantclient,/opt/oracle/instantclient_19_15/' | pecl install pecl install oci8-2.2.0  \
	&& docker-php-ext-install \
			pdo_oci \
	&& docker-php-ext-enable \
			oci8

RUN apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/community/ --allow-untrusted gnu-libiconv
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php

EXPOSE  9000
