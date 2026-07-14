namespace :le_pain do
  task :generate_docker do
    path = File.expand_path('./Dockerfile', Dir.pwd)
    File.open(path, 'w') do |file|
      file.write <<~EOF
      FROM ruby:3.2-slim

      RUN apt-get update -qq \
        && apt-get install -y --no-install-recommends \
          build-essential \
          git \
          curl \
        && rm -rf /var/lib/apt/lists/*

      WORKDIR /app

      COPY Gemfile* ./

      RUN bundle install \
        --deployment \
        --jobs 8 \
        --retry 3

      COPY . /app

      ENV APP_ENV=docker

      EXPOSE 3000

      CMD ["/app/bin/start_service.sh"]

      EOF
    end
    puts "Dockerfile generated at #{path}"
  end
end
