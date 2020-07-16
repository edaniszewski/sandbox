#!/usr/bin/env bash
#
# release.sh
#
# A script to simplify cutting a new tag for a helmfile release.
# When changes are made to a helmfile release, we want to create
# a tagged version so we can identify a specific version of the
# helmfile when using it in a deployment.
#
# This script adds a bit of automation around this process. It:
#  • creates a new tag following the format: {{ app name }}-{{ version }}
#  • allows you to specify a changelog message
#  • enumerates the commits from the previous tag
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
RELEASE_MSG_FILE="RELEASE_MSG"
COMMIT_MSG_FILE="COMMIT_MSG"

function helptext {
cat <<USAGE
  heres some text
USAGE
exit 0
};

PRINT_HELP=0
MAJOR_RELEASE=0
MINOR_RELEASE=0
YOLO_RELEASE=0
MESSAGE=""
POSITIONAL=()

while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in
    -m|--message)
      MESSAGE="$2"
      shift
      shift
      ;;
    -h|--help)
      PRINT_HELP=1
      shift
      ;;
    --major)
      MAJOR_RELEASE=1
      shift
      ;;
    --minor)
      MINOR_RELEASE=1
      shift
      ;;
    -y)
      YOLO_RELEASE=1
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
    esac
done


if [ ${PRINT_HELP} -eq 1 ]; then
  helptext
  exit 0
fi

if [ ${MAJOR_RELEASE} -eq 1 ] && [ ${MINOR_RELEASE} -eq 1 ]; then
  echo -e "${RED}error${NC}: cannot specify both '--major' and '--minor' flags"
  exit 1
fi

if [ ${#POSITIONAL[@]} -eq 0 ]; then
  echo -e "${RED}error${NC}: no application specified for release"
  exit 1
fi

if [ ${#POSITIONAL[@]} -gt 1 ]; then
  echo -e "${RED}error${NC}: multiple applications specified for release (${POSITIONAL[*]})"
  exit 1
fi

application=${POSITIONAL[0]}
echo "application: ${application}"

readarray -d $'\n' -t all_tags <<< "$(git tag | sort)"
app_tags=()
for tag in "${all_tags[@]}"; do
  if [[ "$tag" == "${application}-"* ]]; then
    app_tags+=("${tag}")
  fi
done

echo "app tags: ${app_tags[*]}"

new_version=""
prev_tag=""

if [ ${#app_tags[@]} -eq 0 ]; then
  new_version="0.0.1"
else
  prev_tag=${app_tags[-1]}
  IFS='-' read -ra TAG <<< "${prev_tag}"
  IFS='.' read -ra PARTS <<< "${TAG[1]}"
  major=${PARTS[0]}
  minor=${PARTS[1]}
  patch=${PARTS[2]}
  if [ ${MAJOR_RELEASE} -eq 1 ]; then
    major=$((major+1))
    minor=0
    patch=0
  elif [ ${MINOR_RELEASE} -eq 1 ]; then
    minor=$((minor+1))
    patch=0
  else
    patch=$((patch+1))
  fi

  new_version="${major}.${minor}.${patch}"
fi

new_tag="${application}-${new_version}"
echo -e "creating new release: ${GREEN}${new_tag}${NC}"

echo "prev tag: ${prev_tag}"

revision_range=""
if [ -z "${prev_tag}" ]; then
  revision_range="HEAD"
else
  revision_range="${prev_tag}..HEAD"
fi

echo "revision range: ${revision_range}"

readarray -d $'\n' -t commits_since_prev <<< "$(git log "${revision_range}" --oneline --no-decorate)"
release_commits=()
for commit in "${commits_since_prev[@]}"; do
  if [[ "$commit" == *"[${application}]"* ]]; then
    release_commits+=("${commit}")
  fi
done

echo "commits: ${release_commits[*]}"

if [ -z "${MESSAGE}" ]; then
  [ -e "${RELEASE_MSG_FILE}" ]  && rm "${RELEASE_MSG_FILE}"
  ${EDITOR:-nano} "${RELEASE_MSG_FILE}"
  MESSAGE=$(cat "${RELEASE_MSG_FILE}")
  rm "${RELEASE_MSG_FILE}"
fi

echo "message: ${MESSAGE}"

message_str=""
if [ -n "${MESSAGE}" ]; then
  message_str="\n\n${MESSAGE}"
fi

commit_str=""
if [ ${#release_commits[@]} -gt 0 ]; then
  commit_str="\n\n"
  for c in "${release_commits[@]}"; do
    
    commit_str+="* ${c}\n"
  done
fi
echo "commitstr: ${commit_str}"


#commitmsg="${new_tag}${message_str}${commit_str}"
commitmsg="${new_tag}${message_str}"
echo -e "${commitmsg}" > "${COMMIT_MSG_FILE}"
