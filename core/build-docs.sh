#!/bin/bash

# generate docs in a temporary directory
FOUNDRY_PROFILE=docs forge doc --out tmp/amphora-technical-docs

# edit the SUMMARY after the Contracts section
# https://stackoverflow.com/questions/67086574/no-such-file-or-directory-when-using-sed-in-combination-with-find
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' -e '/\[Contracts\]/q' docs/src/SUMMARY.md
else
  sed -i -e '/\[Contracts\]/q' docs/src/SUMMARY.md
fi
# copy the generated SUMMARY, from the tmp directory, without the first 5 lines
# and paste them after the contracts section on the original SUMMARY
tail -n+5 tmp/amphora-technical-docs/src/SUMMARY.md >> docs/src/SUMMARY.md

# delete old generated contracts docs
rm -rf docs/src/solidity/contracts
# there are differences in cp and mv behavior between UNIX and macOS when it comes to non-existing directories
# creating the directory to circumvent them
mkdir -p docs/src/solidity/contracts
# move new generated contracts docs from tmp to original directory
cp -R tmp/amphora-technical-docs/src/solidity/contracts docs/src/solidity/

# delete tmp directory
rm -rf tmp
