#!/bin/bash
# update-rates.sh — Quick helper to update IRS rates and deploy
#
# Usage:
#   ./update-rates.sh          # Edit rates, validate, commit, push
#   ./update-rates.sh --check  # Just validate the current JSON
#
set -e

JSON_FILE="irs-rates.json"

validate() {
    echo "Validating $JSON_FILE..."
    python3 -c "
import json, sys
with open('$JSON_FILE') as f:
    data = json.load(f)
errors = []
if data.get('schemaVersion') != 1: errors.append('schemaVersion must be 1')
for year, yd in data.get('taxYears', {}).items():
    for f in ['standardMileageRate','selfEmploymentTaxRate','selfEmploymentMultiplier','socialSecurityWageBase']:
        if f not in yd: errors.append(f'{year}: Missing {f}')
    if 'brackets' in yd:
        for status in ['single','married_filing_jointly','married_filing_separately','head_of_household']:
            b = yd['brackets'].get(status, [])
            if not b: errors.append(f'{year}: No brackets for {status}')
            elif [x['threshold'] for x in b] != sorted([x['threshold'] for x in b]):
                errors.append(f'{year}: Brackets not ascending for {status}')
if errors:
    for e in errors: print(f'  ERROR: {e}')
    sys.exit(1)
print(f'  Valid! {len(data[\"taxYears\"])} tax years, last updated: {data[\"lastUpdated\"]}')
"
}

if [ "$1" = "--check" ]; then
    validate
    exit 0
fi

echo "Opening $JSON_FILE for editing..."
${EDITOR:-nano} "$JSON_FILE"

validate

TODAY=$(date +%Y-%m-%d)
echo ""
read -p "Update lastUpdated to $TODAY? [Y/n] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    python3 -c "
import json
with open('$JSON_FILE') as f: data = json.load(f)
data['lastUpdated'] = '$TODAY'
with open('$JSON_FILE', 'w') as f: json.dump(data, f, indent=2)
print('  Updated lastUpdated to $TODAY')
"
fi

echo ""
echo "Changes:"
git diff --stat "$JSON_FILE"
echo ""
read -p "Commit and push? [Y/n] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    git add "$JSON_FILE"
    git commit -m "Update IRS rates — $(date +%Y-%m-%d)"
    git push
    echo ""
    echo "Pushed! All GigLedger apps will pick up new rates within 24 hours."
fi
