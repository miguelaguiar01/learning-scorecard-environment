# Dockerfile
FROM php:8.1-apache

# Build arguments for metadata
ARG BUILD_DATE
ARG VCS_REF
ARG PLUGIN_VERSION

# Labels for image metadata
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.source="https://github.com/yourusername/learning-scorecard-environment" \
      org.opencontainers.image.version=$VCS_REF \
      org.opencontainers.image.title="Learning Scorecard Moodle Environment" \
      org.opencontainers.image.description="Moodle 4.4.1 with Learning Scorecard plugin pre-installed" \
      learning-scorecard.plugin.version=$PLUGIN_VERSION

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libpng-dev libjpeg-dev libfreetype6-dev \
    libzip-dev libicu-dev libxml2-dev \
    libcurl4-openssl-dev libssl-dev \
    libldap2-dev unzip wget curl \
    mariadb-client git \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        gd zip intl mysqli pdo_mysql \
        curl xml soap opcache exif

# Enable Apache modules
RUN a2enmod rewrite headers expires deflate

# Copy configuration files
COPY configs/php.ini /usr/local/etc/php/conf.d/moodle.ini
COPY configs/apache-default.conf /etc/apache2/sites-available/000-default.conf

# Download and install Moodle 4.4.1
RUN cd /tmp \
    && wget -q https://github.com/moodle/moodle/archive/v4.4.1.tar.gz \
    && tar -xzf v4.4.1.tar.gz \
    && mv moodle-4.4.1/* /var/www/html/ \
    && rm -rf /tmp/v4.4.1.tar.gz /tmp/moodle-4.4.1

# Create moodledata directory
RUN mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www/html /var/www/moodledata \
    && chmod -R 755 /var/www/html \
    && chmod -R 777 /var/www/moodledata

# Create directory for plugins
RUN mkdir -p /var/www/html/local

# Copy the Learning Scorecard plugin
COPY ./plugins/learning-scorecard-moodle /var/www/html/local/learning_scorecard

# Set proper ownership and permissions
RUN chown -R www-data:www-data /var/www/html/local/learning_scorecard \
    && chmod -R 755 /var/www/html/local/learning_scorecard

EXPOSE 80
CMD ["apache2-foreground"]