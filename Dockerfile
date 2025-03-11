# Base image.
FROM php:8.3-fpm

# Environment variables.
ARG ADMIN_USER=admin
ARG ADMIN_GROUP=admin
ARG WWW_ROOT_PATH=/var/www/sites

# Install basic dependencies.
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    debian-archive-keyring \
    debian-keyring \
    default-libmysqlclient-dev \
    git \
    gnupg \
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
    lsb-release \
    nodejs \
    npm \
    openssh-server \
    rsync \
    screen \
    sudo \
    supervisor \
    unzip \
    vim \
    zip \
    zlib1g-dev \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install D2 CLI.
RUN curl -fsSL https://d2lang.com/install.sh | sh -s -- --prefix /usr/local

# Install Caddy.
RUN curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt-get update \
    && apt-get install -y caddy \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions.
RUN docker-php-ext-configure gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/ \
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
        && pecl install redis && docker-php-ext-enable redis

# Install and configure Xdebug.
RUN pecl install xdebug \
    && docker-php-ext-enable xdebug \
    && mkdir -p /var/log/xdebug \
    && chmod 777 /var/log/xdebug

# Copy Xdebug configuration.
COPY config/php/xdebug.ini /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# Install Composer.
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Configure PHP.
COPY config/php/php.ini /usr/local/etc/php/php.ini

# Configure Caddy.
RUN mkdir -p /etc/caddy/sites.d
COPY config/caddy/Caddyfile /etc/caddy/Caddyfile

# Configure SSH.
RUN mkdir -p /var/run/sshd
COPY config/ssh/sshd_config /etc/ssh/sshd_config

# Create admin user for SSH access.
RUN useradd -m -d /home/${ADMIN_USER} -s /bin/bash ${ADMIN_USER} \
    && usermod -p '*' ${ADMIN_USER} \
    && echo "${ADMIN_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers \
    && chmod 0440 /etc/sudoers \
    && chmod g+w /etc/passwd \
    && mkdir -p /home/${ADMIN_USER}/.ssh \
    && chmod 700 /home/${ADMIN_USER}/.ssh

# Copy authorized keys for admin user.
COPY config/ssh/authorized_keys /home/${ADMIN_USER}/.ssh/authorized_keys
RUN chmod 600 /home/${ADMIN_USER}/.ssh/authorized_keys \
    && chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.ssh

# Create necessary directories for web content and give admin user access.
RUN mkdir -p ${WWW_ROOT_PATH} \
    && chown -R ${ADMIN_USER}:${ADMIN_GROUP} ${WWW_ROOT_PATH} \
    && chmod 770 ${WWW_ROOT_PATH}

# Configure Supervisor.
COPY config/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose ports.
EXPOSE 80 443 22 9123

# Start supervisor.
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
