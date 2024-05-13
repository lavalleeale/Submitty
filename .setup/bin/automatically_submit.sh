#!/usr/bin/env bash


# Testing

curl -X POST -H "Content-Type: application/json" -d '{"message": "hello 😁"}' localhost/api/$1/$2/gradeable/$3/upload 