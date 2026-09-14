#!/bin/bash

#AI use 1
#Company: Anthropic
#Model: Claude Sonnet 5
#Date: 14/09/2026
#Use case:  Help with debugging and quick explanations upon commands
#		and their respective use flags.

#   Helper functions
dec_to_bin8() {
    local membin=""
    local tmp=$1
    local weight
    local bit
 
    for weight in 128 64 32 16 8 4 2 1
    do
        if (( tmp >= weight )); then
            bit=1
            tmp=$(( tmp - weight ))
        else
            bit=0
        fi
        membin="$membin$bit"
    done
 
    echo "$membin"
}
 
dec_to_bin2() {
    local regbin=""
    local tmp=$1
    local weight
    local bit
 
    for weight in 2 1
    do
        if (( tmp >= weight )); then
            bit=1
            tmp=$(( tmp - weight ))
        else
            bit=0
        fi
        regbin="$regbin$bit"
    done
 
    echo "$regbin"
}

#   Check for the argument(s).
if [ "$#" -eq 0 ]; then
    echo "usage: no argument is provided"
    exit 1
elif [ "$#" -eq 1 ]; then
    if [ -e "$1" ] && [ -f "$1" ]; then
        file="$1"
    else
        echo "usage: input is not a file or it does not exist"
        exit 1
    fi
else
    echo "usage: more than one arguments are provided"
    exit 1
fi

#   Check the file extension
if [[ "$file" != *.vsc ]]; then
    echo "usage: input does not have the extension .vsc"
    exit 1
fi

#   Check if the file is empty
if [ ! -s "$file" ]; then
    echo "usage: the file is empty - no .bin file is produced"
    exit 1
fi

binfile="${file%.vsc}.bin"

#   Read the file into an array
lines=()
while IFS= read -r line || [ -n "$line" ]; do
    lines+=("$line")
done < "$file"
 
if [ "${#lines[@]}" -eq 0 ]; then
    echo "usage: the input file does not contain any line"
    exit 1
fi
 
#   Check the first line
n_values="${lines[0]}"

if [ "$n_values" != "0" ] && [ "$n_values" != "2" ]; then
    echo "Line 1 can only be 0 or 2"
    exit 1
fi
 
byteArray=()
insStart=0

#   QUIT program
if [ "$n_values" -eq 0 ]; then
    echo "It is a QUIT program"
    if [ "${#lines[@]}" -lt 2 ]; then
        echo "A QUIT program must contain the line QUIT,0,0"
        exit 1
    fi

    #   exact match required
    if [ "${lines[1]}" != "QUIT,0,0" ]; then
        echo "When line 1 is 0, line 2 must be exactly QUIT,0,0"
        exit 1
    fi
 
    insStart=1
 
else
    #   ADD/SUB program
    echo "It is an ADD/SUB program"
    echo "************"
 
    dataArray=()
 
    for i in 1 2
    do
        val="${lines[$i]}"
 
        if ! [[ "$val" =~ ^[0-9]+$ ]]; then
            echo "Line $(( i + 1 )) must be a positive integer."
            exit 1
        fi
 
        if [ "$val" -lt 0 ] || [ "$val" -gt 128 ]; then
            echo "Line $(( i + 1 )) must be in the range [0-128]."
            exit 1
        fi
 
        dataArray+=("$(dec_to_bin8 "$val")")
    done
 
    # the static values are written before the instructions
    byteArray+=("${dataArray[@]}")
 
    insStart=3
fi

#   Proceed to instruction part
insCount=0
sawQuit=0
 
i=$insStart
while [ "$i" -lt "${#lines[@]}" ]
do
    line="${lines[$i]}"
    i=$(( i + 1 ))
 
    if [ "$insCount" -ge 100 ]; then
        echo "A program can contain a maximum of 100 instructions."
        exit 1
    fi
 
    if [ "${#line}" -gt 11 ]; then
        echo "The line $line is too long to be a valid instruction."
        exit 1
    fi
 
    #   split the line on commas into 3 parts (instruction, register, memory)
    IFS=',' read -r ins reg mem <<< "$line"
 
    #   validate the instruction name (case sensitive)
    if ! echo "$ins" | grep -qxE "LOAD|STORE|ADD|SUB|QUIT|PRINT"; then
        echo "The instruction part of $line is not a valid instruction."
        exit 1
    fi
 
    # Get opcode binary value
    if [ "$ins" = "LOAD" ]; then
        opcode="000001"
    elif [ "$ins" = "STORE" ]; then
        opcode="000010"
    elif [ "$ins" = "ADD" ]; then
        opcode="000011"
    elif [ "$ins" = "SUB" ]; then
        opcode="000100"
    elif [ "$ins" = "QUIT" ]; then
        opcode="001000"
    elif [ "$ins" = "PRINT" ]; then
        opcode="001001"
    fi
 
    #   Check if the register is valid
    if [ -z "$reg" ]; then
        echo "The reg. part of $line is empty."
        exit 1
    fi
 
    if ! [[ "$reg" =~ ^[0-9]+$ ]]; then
        echo "The reg. part of $line is not a number."
        exit 1
    fi
 
    if (( reg < 0 || reg > 3 )); then
        echo "The reg. part of $line is out of range."
        exit 1
    fi
 
    #   Validate the memory part [0-255]
    if [ -z "$mem" ]; then
        echo "The mem. part of $line is empty."
        exit 1
    fi
 
    if ! [[ "$mem" =~ ^[0-9]+$ ]]; then
        echo "The mem. part of $line is not a number."
        exit 1
    fi
 
    if (( mem < 0 || mem > 255 )); then
        echo "The mem. part of $line is out of range."
        exit 1
    fi
 
    #   QUIT and PRINT have fixed operands
    if [ "$ins" = "QUIT" ] && { [ "$reg" -ne 0 ] || [ "$mem" -ne 0 ]; }; then
        echo "QUIT must be written as QUIT,0,0"
        exit 1
    fi
 
    if [ "$ins" = "PRINT" ] && [ "$mem" -ne 0 ]; then
        echo "The mem. part of $line must be 0 for PRINT."
        exit 1
    fi
 
    #   Build the 2 bytes for this instruction
    regbin=$(dec_to_bin2 "$reg")
    membin=$(dec_to_bin8 "$mem")
 
    byteArray+=("$opcode$regbin")   # byte 1: opcode + register
    byteArray+=("$membin")          # byte 2: memory address
 
    insCount=$(( insCount + 1 ))
 
    if [ "$ins" = "QUIT" ]; then
        sawQuit=1
        break
    fi
done
 
if [ "$sawQuit" -eq 0 ]; then
    echo "The program does not contain a QUIT,0,0 instruction."
    exit 1
fi

#   Clearing binfile
> "$binfile"

for bits in "${byteArray[@]}"
do
    hex=$(printf '%02X' "$(( 2#$bits ))")
    printf "\x$hex" >> "$binfile"
done
 
# Print
 
echo "**********"
echo "The content of the .bin file is:"
xxd -p -c 1 "$binfile"
 
exit 0
