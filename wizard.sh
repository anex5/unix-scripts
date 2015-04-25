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
	usage(){ echo "Usage: $0 m: message o: options" }
	test $# -lt 1 && { echo "No options found!"; return 1; }
	while getopts "m:o:" opt; do
		case $opt in
		m) let $((step++)) && echo -e "n$step. $OPTARGn";;
		o) options=$OPTARG;;
		h|?) usage && return 0;;
		*) echo "No reasonable options found!" && usage;;
		esac
	done
	shift $(($OPTIND--))
	cases=$@
	select selected in $options exit
	do
		case $selected in 
		"exit") die "Exiting...";;
		*) case $selected in $cases esac;;
		esac
		break
	done
}

wizard m="First step" o="first second skip" skip)return 0;; *)var=$selected;; 
