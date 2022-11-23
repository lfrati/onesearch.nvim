#!/bin/bash
LINES=$(awk '!/^ *--/ && !/^$/{c++}END{print c}' $1)
THRESHOLD=500
if [[ $LINES -gt $THRESHOLD ]] 
then
    BADGE_COLOR="red"
else
    BADGE_COLOR="brightgreen"
fi
printf '{\n  "schemaVersion": 1,\n  "label": "LOC",\n  "message": "%s",\n  "color": "%s"\n}' "$LINES" "$BADGE_COLOR"
