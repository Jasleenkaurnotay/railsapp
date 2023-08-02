# config/initializers/elasticsearch.rb


require 'elasticsearch'
# Use the environment variables for AWS OpenSearch master username and password
elasticsearch_username = ENV['ELASTICSEARCH_USERNAME']
elasticsearch_password = ENV['ELASTICSEARCH_PASSWORD']
elasticsearch_url= ENV['ELASTICSEARCH_URL']

# Configure Elasticsearch
Elasticsearch::Model.client = Elasticsearch::Client.new(
  #url: 'https://search-rails-x6dc7rxmei6uuoeqa3iixqyk2a.us-east-1.es.amazonaws.com',
  url: elasticsearch_url,
  user: elasticsearch_username,
  password: elasticsearch_password
)

