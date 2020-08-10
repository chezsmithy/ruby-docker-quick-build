# By default unless build args are specified
# Then bundle from the gemfile
ARG BUNDLE_TYPE=gemfile

FROM ruby:2.6.5-alpine AS base

# Add dockerize to allow waiting for other local resources (database, etc.)
RUN apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing \
  dockerize

RUN apk update && \
  apk add --virtual build-dependencies \
    build-base tzdata openssl-dev git && \
  apk add --virtual dev-tools \
    yarn less bash openssl && \
  apk add --no-cache nodejs mariadb-dev mysql-client ca-certificates curl

# Add certificates to image
COPY ./certificates /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Add non-root user
RUN addgroup -g 500 appuser
RUN adduser -D -s /bin/bash -h /home/appuser -G appuser appuser

ENV HOME=/home/appuser
ENV APP_HOME=$HOME/project

RUN mkdir $APP_HOME
RUN mkdir -p $APP_HOME/log
RUN mkdir -p $APP_HOME/tmp

RUN chown -R appuser:appuser $APP_HOME
RUN chown -R appuser:appuser /usr/local
RUN chmod a+rwx -R $HOME

# Add in yarn and node tools
FROM base AS yarn_base

USER appuser
RUN yarn global add stylelint stylelint-scss stylelint-config-standard jshint

FROM base as bundle

WORKDIR $APP_HOME
COPY --chown=appuser:appuser Gemfile Gemfile.lock $APP_HOME/
COPY --chown=appuser:appuser ./vendor $APP_HOME/vendor

FROM bundle as bundle_accelerated
ONBUILD RUN echo "Bundle copied from latest image."
ONBUILD COPY --from=my_image_base:latest /usr/local/bundle/ /usr/local/bundle/

FROM bundle as bundle_gemfile
ONBUILD RUN echo "Bundle from scratch."

FROM bundle_${BUNDLE_TYPE} as with_bundle

RUN gem install bundler -v "2.1.4"
RUN bundle config
RUN bundle install --local --jobs=3 --retry=3 --full-index

FROM with_bundle as local

COPY --from=yarn_base $HOME/.config $HOME/.config
RUN ln -s $HOME/.config/yarn/global/node_modules/.bin/jshint /usr/local/bin/jshint
RUN ln -s $HOME/.config/yarn/global/node_modules/.bin/stylelint /usr/local/bin/stylelint

# Rails env for this stage
ENV RAILS_ENV=development

USER appuser
WORKDIR $APP_HOME

FROM with_bundle as production

# if production then clean installed development/test gems and apk packages
RUN bundle config --global --without=development test
RUN bundle clean --force
RUN rm -rf /usr/local/bundle/cache/*.gem \
 && find /usr/local/bundle/gems/ -name "*.c" -delete \
 && find /usr/local/bundle/gems/ -name "*.o" -delete
 RUN apk del build-dependencies dev-tools \
    && rm -rf /var/cache/apk/*

# Rails env when building for production
ENV RAILS_ENV=production

USER appuser
WORKDIR $APP_HOME

# if production add the rails app
COPY --chown=appuser:appuser . $APP_HOME
# Remove folders not needed in resulting image
RUN rm -rf spec features
