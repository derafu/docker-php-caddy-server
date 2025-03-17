# Base image.
FROM php:8.3-fpm

# Arguments.
ARG CADDY_DEBUG=
ARG WWW_ROOT_PATH=/var/www/sites
ARG WWW_USER=admin
ARG WWW_GROUP=www-data

# Expose ports.
EXPOSE 22 80 443 9090

# Run a lot of commands :)
RUN \
    \
    # Install basic dependencies.
    apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    at \
    ca-certificates \
    cron \
    curl \
    debian-archive-keyring \
    debian-keyring \
    default-libmysqlclient-dev \
    git \
    gnupg \
    jq \
    libfreetype6-dev \
    libgd-dev \
    libicu-dev \
    libjpeg62-turbo-dev \
    libonig-dev \
    libpng-dev \
    libpq-dev \
    libsqlite3-dev \
    libxml2-dev \
    libzip-dev \
    logrotate \
    lsb-release \
    mutt \
    nano \
    openssh-server \
    rsync \
    screen \
    sudo \
    supervisor \
    unzip \
    vim \
    zip \
    zlib1g-dev \
    \
    # Install Node.js.
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    \
    # Install D2 CLI.
    && curl -fsSL https://d2lang.com/install.sh | sh -s -- --prefix /usr/local \
    \
    # Install Caddy.
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends caddy \
    && rm -rf /var/lib/apt/lists/* \
    \
    # Install PHP extensions.
    && docker-php-ext-configure gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/ \
    && docker-php-ext-install -j$(nproc) \
        bcmath \
        exif \
        gd \
        intl \
        mbstring \
        opcache \
        pdo_mysql \
        pdo_pgsql \
        pdo_sqlite \
        soap \
        sockets \
        xml \
        zip \
        && pecl install redis && docker-php-ext-enable redis \
    \
    # Install and configure Xdebug.
    && pecl install xdebug \
    && docker-php-ext-enable xdebug \
    && mkdir -p /var/log/xdebug \
    && chmod 777 /var/log/xdebug \
    \
    # Create PHP socket directory.
    && mkdir -p /var/run/php && chown www-data:www-data /var/run/php \
    \
    # Create SSH directory.
    && mkdir -p /var/run/sshd \
    \
    # Create admin user for SSH access.
    && useradd -m -d /home/${WWW_USER} -s /bin/bash ${WWW_USER} \
    && usermod -p '*' ${WWW_USER} \
    && echo "${WWW_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
    && chmod 0440 /etc/sudoers \
    && chmod g+w /etc/passwd \
    && mkdir -p /home/${WWW_USER}/.ssh \
    && chmod 700 /home/${WWW_USER}/.ssh \
    && ssh-keyscan -t rsa github.com >> /home/${WWW_USER}/.ssh/known_hosts \
    && chmod 600 /home/${WWW_USER}/.ssh/known_hosts \
    && chown ${WWW_USER}: /home/${WWW_USER}/.ssh/known_hosts \
    \
    # Create necessary directories for web content and give admin user access.
    && mkdir -p ${WWW_ROOT_PATH} \
    && chown -R ${WWW_USER}:${WWW_GROUP} ${WWW_ROOT_PATH} \
    && chmod 770 ${WWW_ROOT_PATH} -R \
    && ln -s ${WWW_ROOT_PATH} /home/${WWW_USER}/sites \
    \
    # Allow www-data and ${WWW_USER} users to add jobs to the at queue.
    && echo "www-data" >> /etc/at.allow \
    && echo "${WWW_USER}" >> /etc/at.allow \
    \
    # Add SSH known hosts.
    && mkdir -p /etc/ssh \
    && ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts \
    && chmod 644 /etc/ssh/ssh_known_hosts

# Copy authorized keys for the user.
COPY config/ssh/authorized_keys /home/${WWW_USER}/.ssh/authorized_keys
RUN chmod 600 /home/${WWW_USER}/.ssh/authorized_keys \
    && chown -R ${WWW_USER}:${WWW_USER} /home/${WWW_USER}/.ssh \
    \
    # Add SSH key for www-data user.
    && mkdir -p /var/www/.ssh \
    && ssh-keygen -t rsa -b 4096 -N "" -C "www-data@localhost" -f /var/www/.ssh/id_rsa -q \
    && cat /var/www/.ssh/id_rsa.pub >> /home/${WWW_USER}/.ssh/authorized_keys \
    && chown -R www-data:www-data /var/www/.ssh \
    && chmod 700 /var/www/.ssh \
    && chmod 600 /var/www/.ssh/id_rsa

# Add configuration to .bashrc of the user.
COPY config/bash/bashrc /root/add-to-bashrc
RUN cat /root/add-to-bashrc >> /home/${WWW_USER}/.bashrc \
    && rm -f /root/add-to-bashrc

# Configure PHP.
COPY config/php/php.ini /usr/local/etc/php/php.ini
COPY config/php/www.conf /usr/local/etc/php-fpm.d/zz-docker.conf
COPY config/php/xdebug.ini /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
RUN if [ -n "${CADDY_DEBUG}" ]; then \
        # Disable OPCache by default in development mode.
        sed -i 's/^opcache.enable = 1/opcache.enable = 0/' /usr/local/etc/php/php.ini; \
        sed -i 's/^opcache.enable_cli = 1/opcache.enable_cli = 0/' /usr/local/etc/php/php.ini; \
        # Enable Xdebug by default in development mode with debug mode.
        sed -i 's/^;zend_extension=xdebug.so/zend_extension=xdebug.so/' /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini; \
        sed -i 's/^xdebug.mode = off/xdebug.mode = debug/' /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini; \
    fi

# Install Composer.
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Configure Caddy.
COPY config/caddy/Caddyfile /etc/caddy/Caddyfile

# Configure SSH.
COPY config/ssh/sshd_config /etc/ssh/sshd_config

# Configure Logrotate.
COPY config/logrotate/deployer /etc/logrotate.d/deployer

# Configure Cron.
COPY config/cron/logrotate /etc/cron.d/logrotate

# Configure Supervisor.
COPY config/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Use an entrypoint.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Start supervisor (default process of the container).
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
