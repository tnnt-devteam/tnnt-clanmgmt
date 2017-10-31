#!/bin/bash

if [ -f devnull-web.pid ]; then
  kill -QUIT $(cat devnull-web.pid)
fi
