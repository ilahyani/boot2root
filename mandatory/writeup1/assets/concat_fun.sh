#!/bin/bash

grep -l 'file' * \
| awk -F'file' '
{
    cmd = "grep -m1 file \"" $0 "\""
    cmd | getline line
    close(cmd)
    split(line, a, "file")
    print a[2] "\t" $0
}
' \
| sort -n \
| cut -f2- \
| xargs cat > fun.c
