# Serves the patient app as Flutter web. The mobile app itself cannot be
# containerised -- it needs a device or emulator -- so this is the browser build,
# which is enough to demo every screen.
#
# Not pinned to a patch version on purpose: pubspec.yaml needs Dart ^3.12.2 and
# the only pinned tag published for this minor (3.44.0) predates it. Pin here the
# moment a matching tag exists.
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app

# The API base URL is compiled into the bundle, so it is a build arg. The browser
# runs on the host, so it reaches the API on the host's published port -- not on
# the compose network name.
ARG API_URL=http://localhost:4000
ARG GOOGLE_SERVER_CLIENT_ID=

# Firebase client config. Public values that ship in every client build anyway --
# access is enforced by the backend verifying the ID token, not by hiding these.
ARG FIREBASE_API_KEY=
ARG FIREBASE_APP_ID=
ARG FIREBASE_PROJECT_ID=
ARG FIREBASE_MESSAGING_SENDER_ID=
ARG FIREBASE_AUTH_DOMAIN=

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release \
      --dart-define=API_URL=$API_URL \
      --dart-define=GOOGLE_SERVER_CLIENT_ID=$GOOGLE_SERVER_CLIENT_ID \
      --dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY \
      --dart-define=FIREBASE_APP_ID=$FIREBASE_APP_ID \
      --dart-define=FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID \
      --dart-define=FIREBASE_MESSAGING_SENDER_ID=$FIREBASE_MESSAGING_SENDER_ID \
      --dart-define=FIREBASE_AUTH_DOMAIN=$FIREBASE_AUTH_DOMAIN

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
# Flutter web is a single-page app: unknown paths must fall through to index.html
# or a refresh on any route 404s.
#
# The cache rules matter as much as the fallback. Flutter registers a service
# worker that will happily serve the previous build forever -- a rebuilt image
# looks like it did nothing, and even a hard refresh keeps showing the old app,
# because the worker answers before the network does. index.html and the worker
# itself must therefore never be cached; everything else Flutter emits is content
# hashed, so it can be cached hard.
COPY <<'CONF' /etc/nginx/conf.d/default.conf
server {
  listen 80;
  root /usr/share/nginx/html;

  location = /index.html {
    add_header Cache-Control "no-cache, no-store, must-revalidate" always;
  }
  location = /flutter_service_worker.js {
    add_header Cache-Control "no-cache, no-store, must-revalidate" always;
  }
  location = /version.json {
    add_header Cache-Control "no-cache, no-store, must-revalidate" always;
  }

  location /assets/ {
    try_files $uri =404;
    add_header Cache-Control "public, max-age=31536000, immutable" always;
  }

  location / { try_files $uri $uri/ /index.html; }
}
CONF
EXPOSE 80
