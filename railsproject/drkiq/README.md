# README

# Using Terraform to deploy RAILS application to AWS

A customer RAILS application has been built and dockerized with companion services: Sidekiq, Redis and Postgresql

A brief summary of the deployment process is:

- Dockerized images for the Rails application - drkiq and Sidekiq were first     uploaded to AWS ECR registry.
- We configured the RAILS application's compose file to utilize AWS login credentials, AWS REDIS ElastiCache cluster and AWS OpenSearch
- First we exposed the application on an Application Load balancer placed before the AWS ECS cluster
- After the above was done, we utilized the Terraform code to deploy the entire AWS infrastructure including S3 bucket, AWS Elastic Cache Endpoint, AWS Open Search, ECS cluster and related cluster services and task definitions.
