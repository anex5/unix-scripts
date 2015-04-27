#!/bin/bash
step=0
write_save=0
save_name=""
selected=""

die(){
	test $# -gt 0 && echo $*
	exit 0
}

wizard(){
	usage(){
		echo "Usage: $0 -m: message -o: options string -c option:command"
	}
	[ $# -lt 1 ] && { echo "No options found!"; return 1; }
	declare -A cases
	declare -a options
	local ix=0
	while getopts "m:c:o:h?" opt; do
		case $opt in
		m) let $((step++)); echo -e "\n$step. $OPTARG\n";;
		o) options[${#options[*]}]="$OPTARG";;
		c) cases["${OPTARG%%:*}"]="${OPTARG##*:}";;
		h|\?) usage && return 0;;
		esac
	done
	shift $((OPTIND-1))
	select selected in ${options[@]}
	do
		[ -n "${selected}" ] && { ${cases[${selected}]}; break; }
	done
	unset -v cases
	unset -v options
}

wizard -m "First step" -o "first second" -o "skip"
