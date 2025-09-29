# ==========================
# Stage 1: Composer dependencies
# ==========================
FROM composer:2 AS vendor

WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-scripts --no-dev --prefer-dist --optimize-autoloader
COPY . .
RUN composer dump-autoload


# ==========================
# Stage 2: Node (Vite build)
# ==========================
FROM node:20 AS frontend

WORKDIR /app
COPY package*.json vite.config.* ./
RUN npm install
COPY . .
COPY --from=vendor /app/vendor ./vendor
RUN npm run build


# ==========================
# Stage 3: PHP + Unit (final image)
# ==========================
FROM unit:1.34.1-php8.3

# Install dependencies untuk PHP extensions
RUN apt update && apt install -y \
    curl unzip git libicu-dev libzip-dev libpng-dev libjpeg-dev libfreetype6-dev libssl-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) pcntl opcache pdo pdo_mysql intl zip gd exif ftp bcmath \
    && pecl install redis \
    && docker-php-ext-enable redis

# Custom PHP settings
RUN echo "opcache.enable=1" > /usr/local/etc/php/conf.d/custom.ini \
    && echo "opcache.jit=tracing" >> /usr/local/etc/php/conf.d/custom.ini \
    && echo "opcache.jit_buffer_size=256M" >> /usr/local/etc/php/conf.d/custom.ini \
    && echo "memory_limit=512M" > /usr/local/etc/php/conf.d/custom.ini \
    && echo "upload_max_filesize=64M" >> /usr/local/etc/php/conf.d/custom.ini \
    && echo "post_max_size=64M" >> /usr/local/etc/php/conf.d/custom.ini

COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

WORKDIR /var/www/html

RUN mkdir -p storage bootstrap/cache

# Copy source code
COPY . .

# Copy vendor & build asset
COPY --from=vendor /app/vendor ./vendor
COPY --from=frontend /app/public/build ./public/build

# Permission
RUN chown -R unit:unit storage bootstrap/cache vendor public/build \
    && chmod -R 775 storage bootstrap/cache vendor public/build

# Optimize Laravel
RUN composer install --no-dev --optimize-autoloader --prefer-dist --no-interaction \
    && php artisan config:clear \
    && php artisan route:clear \
    && php artisan view:clear \
    && php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache

COPY unit.json /docker-entrypoint.d/unit.json

EXPOSE 8000
CMD ["unitd", "--no-daemon"]