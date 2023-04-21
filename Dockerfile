# Use the official Ruby 2.7.5 image as the base image
FROM ruby:2.7.5

# Set the working directory within the container
WORKDIR /app

# Copy the Gemfile and Gemfile.lock into the container
COPY Gemfile Gemfile.lock ./

# Install bundler and the dependencies specified in Gemfile
RUN gem install bundler && bundle install

# Copy the application code into the container
COPY . .

# Install Node.js, Yarn, and apt-utils
RUN apt-get update && \
  apt-get install -y --no-install-recommends apt-utils && \
  curl -sL https://deb.nodesource.com/setup_16.x | bash - && \
  apt-get install -y nodejs && \
  npm install --global yarn

# Precompile assets
RUN yarn install --check-files --production
RUN RAILS_ENV=production \
  NODE_ENV=production \
  SECRET_KEY_BASE=$(bundle exec rails secret) \
  bundle exec rails assets:precompile

# Expose the port that the application will run on
EXPOSE 3000

# Start the application server
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]



