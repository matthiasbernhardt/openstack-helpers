#! /bin/bash
# 2018 - d.schwabe@syseleven.de, m.bernhardt@syseleven.de
# Use user password if defined or generate random if nothing defined.

echo "# SysEleven Secrets Generator"

if [[ -n "${1/[ ]*\n/}" ]] ; then
  # execute if the the variable is not empty and contains non space characters
  password4ss="$1"
else
  # execute if the variable is empty or contains only spaces
  #randomstring=$(cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
  #password4ss=$randomstring
  password4ss="$(pwgen 32 1)"
fi
generatedsecretsurl="$(curl -s -X POST -d "plain&secret=$password4ss" "https://secrets.syseleven.de/" )"

#echo "Password: $password4ss"
echo "Generated secrets URL:"
echo "$generatedsecretsurl"
while true ; do
  echo -n "$password4ss" | pbcopy
  echo "PASSWORD copied to clipboard!"
  echo "------"
  read -p "# Press enter to copy secrets URL to clipboard."
  echo -n "$generatedsecretsurl" | pbcopy
  echo "SECRETS URL copied to clipboard!"
  echo "------"
  read -p "# Press enter to copy PASSWORD to clipboard."
done

