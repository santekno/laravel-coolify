# ==========================
# Stage 1: Build frontend assets
# ==========================
FROM node:20 AS frontend

WORKDIR /app

# Copy package.json & package-lock.json dulu biar cache lebih efektif
COPY package*.json vite.config.* ./

# Install dependencies
RUN npm install

# Copy semua source code (termasuk resources/)
COPY . .

# Build asset untuk production
RUN npm run build

# ==========================
# Stage 2: PHP + Unit (final image)
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

# Copy Composer
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Set workdir
WORKDIR /var/www/html

# Buat folder Laravel penting
RUN mkdir -p /var/www/html/storage /var/www/html/bootstrap/cache

# Copy semua source code
COPY . .

# Copy hasil build frontend dari stage Node
COPY --from=frontend /app/public/build ./public/build

# Permission Laravel folders
RUN chown -R unit:unit storage bootstrap/cache public/build \
    && chmod -R 775 storage bootstrap/cache public/build

# Install dependency Laravel
RUN composer install --prefer-dist --optimize-autoloader --no-interaction

# Laravel cache optimization (opsional tapi bagus untuk production)
RUN php artisan config:clear \
    && php artisan route:clear \
    && php artisan view:clear \
    && php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache

# Copy Unit config
COPY unit.json /docker-entrypoint.d/unit.json

EXPOSE 8000

CMD ["unitd", "--no-daemon"]