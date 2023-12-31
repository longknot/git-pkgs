#!/bin/bash

clean_up() {
  rm -R -- foo/ bar/ origin/ pkgs/ 2> /dev/null
}

log_msg() {
  echo -e "\n\033[0;32m[ $1 ... ]\033[0m"
}

# Helper: new release that contains current packages.
pkg_release() {
  pkg=$1
  rev=$2
  log_msg "Release $pkg@$rev"
  echo "$rev" > "$pkg/VERSION"
  git -C $pkg pkgs release -m "Release $rev of $pkg." $rev
}

# Helper: add to 'a' dependent package 'b'.
pkg_add() {
  a=$1
  b=$2
  rev=$3
  log_msg "Add $b@$rev to $a"
  git -C $a pkgs add $b $rev $PWD/$b
}

# Helper: initialize repo (update .gitignore!)
init_repo() {
  git init $1
  git -C $1 config pkgs.name $1
  git -C $1 config pkgs.url "$PWD/$1"
  echo "pkgs" > $1/.gitignore
}

# Repositories used in test.
setup_repos() {
  init_repo pkgs/a
  init_repo pkgs/b
  init_repo pkgs/c
  init_repo pkgs/d
  init_repo pkgs/e

  # We push from foo to a bare repository.
  git init origin --bare

  log_msg "Add origin to foo"

  git init foo
  git -C foo remote add origin "$PWD/origin"
  git -C foo config pkgs.name "pkgs/foo"
  # Let's use 'vendor' as a common prefix for packages (i.e. root folder).
  git -C foo config pkgs.prefix vendor
  echo "vendor" > foo/.gitignore
  #git -C foo config pkgs.name "pkgs/foo"
}

# Add dependencies to the 'foo' repo. Clone into 'bar'.
basic_test() {
  # Set up some package trees.
  pkg_release pkgs/c 1.0
  pkg_release pkgs/d 1.0
  pkg_release pkgs/e 1.0
  pkg_add pkgs/e pkgs/d 1.0
  pkg_release pkgs/c 1.1
  pkg_add pkgs/a pkgs/c 1.0
  pkg_add pkgs/a pkgs/d 1.0
  pkg_release pkgs/a 1.0
  pkg_add pkgs/e pkgs/a 1.0
  pkg_release pkgs/e 1.1
  pkg_add pkgs/d pkgs/e 1.1
  pkg_release pkgs/d 1.1
  pkg_add pkgs/b pkgs/c 1.1
  pkg_add pkgs/b pkgs/d 1.1
  pkg_add pkgs/e pkgs/d 1.1
  pkg_release pkgs/e 1.2
  pkg_release pkgs/b 1.0
  pkg_add pkgs/a pkgs/c 1.1
  pkg_release pkgs/a 1.1
  pkg_release pkgs/a 1.2
  pkg_release pkgs/a 1.3
  pkg_add foo pkgs/a 1.0

  # Release foo@1.0
  pkg_release foo 1.0
  git -C foo pkgs tree

  # Release foo@1.1
  pkg_add foo pkgs/b 1.0
  pkg_release foo 1.1
  git -C foo pkgs tree

  # Release foo@1.2
  pkg_add foo pkgs/a 1.2
  pkg_add foo pkgs/e 1.2

  # exit

  pkg_release foo 1.2
  git -C foo pkgs tree

  log_msg "Push releases to origin."
  git -C foo pkgs push origin 1.0
  git -C foo pkgs push origin 1.1
  git -C foo pkgs push origin 1.2

  log_msg "Clone origin into bar."
  git pkgs clone origin bar 1.2 --all --pkg-name="pkgs/foo"

  # Rollback to a previous release, e.g.:
  # git -C foo pkgs checkout 1.0
  # git -C bar pkgs checkout 1.1
}

clean_up
setup_repos
basic_test
