#!/bin/bash

NPM_PROJECT=express
NPM_DIR="${NPM_PROJECT}_npm_app"
PKGS_DIR="${NPM_PROJECT}_pkgs_app"

mkdir -p $NPM_DIR

# Install npm package with all its dependencies.
( cd $NPM_DIR; npm install ${NPM_PROJECT})

# Migrate npm-based project to git-pkgs.
./npm2pkgs.sh $NPM_DIR $PKGS_DIR "${NPM_PROJECT}_app"

# Create a release.
git -C $PKGS_DIR pkgs release 1.0.0

# Clean up npm.
# rm -rf $NPM_DIR