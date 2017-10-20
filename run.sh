#!/bin/bash

pushd Devnull-Web

starman \
  --port 5000 \
  --pid ../devnull-web.pid \
  --error_log ../devnull-web.error.log \
  --access-log ../devnull-web.access.log \
  --daemonize \
  bin/app.psgi

popd
