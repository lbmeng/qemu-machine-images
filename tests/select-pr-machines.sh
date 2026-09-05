#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
readonly REPO_ROOT
readonly SELECT_TOOL="${REPO_ROOT}/scripts/select-pr-machines.sh"
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

make_machine() {
    local machine_dir="$1"

    mkdir -p -- "${machine_dir}"
    printf 'build specification\n' > "${machine_dir}/build.hcl"
    printf 'machine configuration\n' > "${machine_dir}/machine.conf"
}

commit_fixture() {
    git add --all
    git commit --quiet --message 'test: update selection fixture' \
        --message 'Record file changes to exercise PR machine selection.'
}

reset_fixture() {
    git reset --hard --quiet "${BASE_SHA}"
    git clean -fdq
}

expect_selection() {
    local expected="$1"
    local base_ref="${2:-${BASE_SHA}}"
    local actual

    actual="$("${SELECT_TOOL}" "${TEST_ROOT}" "${base_ref}" HEAD)"
    if [[ "${actual}" != "${expected}" ]]; then
        printf 'expected %s, got %s\n' "${expected}" "${actual}" >&2
        exit 1
    fi
}

expect_failure() {
    local base_ref="${1:-${BASE_SHA}}"

    if "${SELECT_TOOL}" "${TEST_ROOT}" "${base_ref}" HEAD \
        >/dev/null 2>&1; then
        echo 'invalid selection input was accepted' >&2
        exit 1
    fi
}

cd -- "${TEST_ROOT}"
git init --quiet --initial-branch=main
git config user.name 'Selection test'
git config user.email selection-test@example.com
git config commit.gpgsign false
git config core.hooksPath /dev/null

make_machine machine/arm/board-a
make_machine machine/riscv64/board-b
printf 'patch contents\n' > machine/arm/board-a/fix.patch
mkdir -p scripts .github/workflows docs
printf 'builder\n' > scripts/Dockerfile.buildroot
printf 'workflow\n' > .github/workflows/release.yml
printf 'documentation\n' > README.md
printf '1.0.0\n' > VERSION
commit_fixture
BASE_SHA="$(git rev-parse HEAD)"
readonly BASE_SHA
readonly ALL_MACHINES='["machine/arm/board-a","machine/riscv64/board-b"]'

expect_selection '[]'

# Documentation still allows the aggregate workflow check to complete
printf 'updated documentation\n' >> README.md
printf 'guide\n' > docs/guide.md
commit_fixture
expect_selection '[]'

# Machine inputs must trigger a build without requiring a revision bump
for file in build.hcl machine.conf fix.patch finalize-images.sh run.sh; do
    reset_fixture
    printf 'updated input\n' >> "machine/arm/board-a/${file}"
    commit_fixture
    expect_selection '["machine/arm/board-a"]'
done

# Multiple changed files select each machine only once
reset_fixture
printf 'updated input\n' >> machine/arm/board-a/build.hcl
printf 'updated input\n' >> machine/arm/board-a/machine.conf
printf 'updated input\n' >> machine/riscv64/board-b/build.hcl
commit_fixture
expect_selection "${ALL_MACHINES}"

# Shared code, workflows, versioning and unknown inputs rebuild all machines
for file in scripts/Dockerfile.buildroot .github/workflows/release.yml \
    .github/workflows/build-machine.yml .github/workflows/pull-request.yml \
    VERSION .dockerignore shared-input; do
    reset_fixture
    printf 'updated input\n' >> "${file}"
    commit_fixture
    expect_selection "${ALL_MACHINES}"
done

reset_fixture
make_machine machine/aarch64/board-c
commit_fixture
expect_selection '["machine/aarch64/board-c"]'

reset_fixture
git rm --quiet -r machine/arm/board-a
commit_fixture
expect_selection '[]'

reset_fixture
git mv machine/arm/board-a machine/arm/board-c
commit_fixture
expect_selection '["machine/arm/board-c"]'

# Disabling rename detection covers both consumers when an input moves
reset_fixture
git mv machine/arm/board-a/fix.patch machine/riscv64/board-b/fix.patch
commit_fixture
expect_selection "${ALL_MACHINES}"

reset_fixture
git rm --quiet machine/arm/board-a/fix.patch
commit_fixture
expect_selection '["machine/arm/board-a"]'

# A partial machine removal or addition must fail rather than skip validation
for file in build.hcl machine.conf; do
    reset_fixture
    git rm --quiet "machine/arm/board-a/${file}"
    commit_fixture
    expect_failure
done

reset_fixture
mkdir -p machine/arm/incomplete
printf 'configuration\n' > machine/arm/incomplete/machine.conf
commit_fixture
expect_failure

reset_fixture
make_machine 'machine/arm/invalid name'
commit_fixture
expect_failure

reset_fixture
expect_failure nonexistent-base

# Match Actions: compare a PR merge commit with its current base parent
git checkout --quiet -b contribution
printf 'PR change\n' >> machine/arm/board-a/machine.conf
commit_fixture
git checkout --quiet main
printf 'unrelated base change\n' >> machine/riscv64/board-b/machine.conf
commit_fixture
git merge --quiet --no-ff contribution \
    --message 'test: merge contribution fixture' \
    --message 'Test the merged PR tree against its base branch parent.'
expect_selection '["machine/arm/board-a"]' HEAD^1

printf 'PR machine selection tests passed\n'
