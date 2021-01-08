FROM centos:8

MAINTAINER zhaohao731869706@163.com

ENV PHP_VERSION=7.4
ENV LANG=C.UTF-8

RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

#安装依赖包 Install dependencies
RUN yum install -y curl wget openssl-devel gcc-c++ make autoconf zip unzip

RUN curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-8.repo \
    && yum makecache

#安装基础需要组件 Install basic components
RUN dnf install git lsof memcached redis mysql mysql-server telnet vim -y

# 安装php Install php
RUN dnf module reset php \
    && dnf install epel-release -y \
    && dnf install https://rpms.remirepo.net/enterprise/remi-release-8.rpm -y \
    && yes y|dnf module enable php:remi-${PHP_VERSION} -y \
    && dnf install php php-devel libmemcached php-pecl-rdkafka php-gd php-dba php-gmp php-intl php-ldap php-odbc php-soap php-tidy php-pecl-zip php-bcmath php-ast php-pecl-amqp php-pecl-mongodb php-pecl-imagick php-pecl-protobuf php-pecl-memcached php-pecl-memcache php-openssl php-json php-mysqlnd php-sockets php-mbstring boost boost-devel -y
#修改php配置 Modify php configuration
RUN sed -i -e 's@upload_max_filesize = 2M@upload_max_filesize = 100M@g' /etc/php.ini \
    && sed -i -e 's@post_max_size = 8M@post_max_size = 108M@g' /etc/php.ini \
    && sed -i -e 's@memory_limit = 128M@memory_limit = 1024M@g' /etc/php.ini \
    && sed -i -e 's@;date.timezone =@date.timezone = Asia/Shanghai@g' /etc/php.ini
#安装pecl Install pecl
RUN wget http://pear.php.net/go-pear.phar \
    && php go-pear.phar \
    && pecl channel-update pecl.php.net

#使用pecl安装swoole Install swoole using pecl
RUN yes|pecl install swoole \
    && echo "extension=swoole.so" > /etc/php.d/30-swoole.ini \
    && echo "swoole.use_shortname=off" >> /etc/php.d/30-swoole.ini

#安装yasd调试swoole Install yasd to debug swoole
RUN git clone https://github.com/swoole/yasd.git
WORKDIR /yasd
RUN phpize --clean \
    && phpize \
    && ./configure \
    && make clean \
    && make \
    && make install \
    && echo "zend_extension=yasd" >> /etc/php.ini

#安装composer Install composer
WORKDIR /
RUN curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/bin/composer \
    && composer config -g repo.packagist composer https://mirrors.cloud.tencent.com/composer/

#修改redis并启动 Modify redis and start
RUN sed -i -e 's@bind 127.0.0.1@bind 0.0.0.0@g' /etc/redis.conf \
    && sed -i -e 's@protected-mode yes@protected-mode no@g' /etc/redis.conf

#php-redis php-redis
RUN pecl install redis \
    && echo "extension=redis.so" > /etc/php.d/30-redis.ini

#修改memcached配置 Modify memcached configuration
RUN sed -i -e 's@OPTIONS="-l 127.0.0.1,::1"@''@g' /etc/sysconfig/memcached

#mysql配置 mysql configuration
RUN echo "bind-address = 0.0.0.0" >> /etc/my.cnf \
    && echo "mysqlx-bind-address = 0.0.0.0" >> /etc/my.cnf

#写入启动服务脚本 Write start service script
RUN echo -e "#\!/bin/sh \n/usr/sbin/init & \nsystemctl start mysqld &\nsystemctl start redis & \nsystemctl start memcached & \nsystemctl restart mysqld \nmysql -e 'use mysql;update user set host = \"%\" where user = \"root\" and host=\"localhost\";flush privileges;'" > /services_start.sh \
    && chmod +x /services_start.sh
#端口 port
EXPOSE 6379 11211 9501 3306
#执行系统进程（不然无法使用systemctl等系统命令）Execute system processes (otherwise you cannot use system commands such as systemctl)
ENTRYPOINT ["/usr/sbin/init"]
