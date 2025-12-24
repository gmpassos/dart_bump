#!/bin/bash

APIKEY=$1;

dart run bin/dart_bump.dart . --extra-file "lib/src/dart_bump_base.dart=static\\s+final\\s+String\\s+VERSION\\s*=\\s*['\"]([\\w.\\-]+)['\"]" --api-key $APIKEY
