#!/bin/bash


#    pacmanlog2gource - converts a copy of /var/log/pacman.log into a format readable by gource
#    Copyright (C) 2011-2013  Matthias Krüger

#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 1, or (at your option)
#    any later version.

#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.

#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA  02110-1301 USA


# Regarding usage of the arch logo, I asked in #archlinux on irc.freeode.net on
# Friday,  May 25th 2012 , around 12:00 CEST

#11:59 < matthiaskrgr> I made a script which visualizes the pacman logfile (package updates removals etc)
#12:00 < matthiaskrgr> looks like this http://www.youtube.com/watch?v=lCBjzC78t4o
#[...]
#12:00 < matthiaskrgr> and I wondered if I was allowed to display a little arch linux icon at the lower right corner
#12:00 < allanbrokeit> I had seen that on the forums
#[...]
#12:00 < matthiaskrgr> or if there were any problems with it
#12:00 < allanbrokeit> matthiaskrgr: I'd say that is fine
#12:00 < matthiaskrgr> ok thanks :)
#12:01 < matthiaskrgr> I'll quote you in some code comment, just in case... ;)
#12:01 < allanbrokeit> matthiaskrgr: https://wiki.archlinux.org/index.php/DeveloperWiki:TrademarkPolicy
#[...]
#12:02 < allanbrokeit> I'd say this falls in the advocacy section



# set -x

export LANG=C


# variables
DATADIR=~/.pacmanlog2gource

exit_() {
	if [ ! `echo "$*" | grep -o "^-.[^\ ]*n\|\-n"` ] ; then
		if [ -f ${DATADIR}/lock ] ; then
			rm ${DATADIR}/lock
		fi
		exit $*
	fi
}

sizecalc() {
	outputunit=b
	input=$1
	if [ ${input} == 0 ] ; then
		echo -n "0 b"
	else
		outputval=${input}
		((outputkilo=${outputval}/1024))
		if [ ! "${outputkilo}" == 0 ] ; then
			outputunit=kb
			outputval=${outputkilo}
			((outputmega=${outputkilo}/1024))
			if [ ! "${outputmega}" == 0 ] ; then
				outputunit=Mb
				outputval=${outputmega}
				((outputgiga=${outputmega}/1024))
				if [ ! "${outputgiga}" == 0 ] ; then
					outputunit=Gb
					outputval=${outputgiga}
				fi
			fi
		fi
		echo "${outputval} ${outputunit}"
	fi
}

LOGTOBEPROCESSED=${DATADIR}/pacman_purged.log
PACMANLOG=/var/log/pacman.log
LOGNOW=${DATADIR}/pacman_now.log
LOG=${DATADIR}/pacman_gource_tree.log

UPDATE="true"
COLOR="true"
FFMPEGPOST="false"
GOURCEPOST="false"
INFORMATION="false"
LOGO="false"
QUIET="false"

RED='\e[1;31m'
GREEN='\e[3;32m'
GREENUL='\e[4;32m'
WHITEUL='\e[4;02m'
NC='\e[0m'

TIMECOUNTCOOKIE=0

VERSION="2.0.3"

FILENAMES=' '


if [ `echo "$*" | grep -o "^-.[^\ ]*d\|\-d"` ] ; then
	echo "Debug mode..."
	set -x
fi
# check if we already have the datadir, if we don't have it, create it
if [ ! -d "${DATADIR}" ] ; then
	# workaround to not have colors displayed if we use -c option
	if [[ `echo "$*" | grep -o "^-.[^\ ]*c\|\-c"` ]] ; then
		echo -e "No directory ${DATADIR} found, creating one."
	else
		echo -e "No directory ${WHITEUL}${DATADIR}${NC} found, creating one."
	fi
	# if we cannot create the datadir (wtf!?), complain
	if  mkdir "${DATADIR}"  ; then
		:
	else
		echo -e "ERROR: Unable to create ${DATADIR}" >&2
		exit_ 1
	fi
fi


if [ -f ${DATADIR}/lock ] ; then
	echo "FATAL: lockfile exists."
	echo "Please wait until current instance of pacmanlog2gource is done and re-run or"
	echo "remove ${DATADIR}/lock manually and re-run."
	exit 4
fi
if [ ! `echo "$*" | grep -o "^-.[^\ ]*n\|\-n"` ] ; then
	touch ${DATADIR}/lock
fi

# create a checksum of the log-generating part of the script
PATHTOSCRIPT=$0
COMPATIBILITY_CHECKSUM=`cat ${PATHTOSCRIPT} | sed -e '/COMPATIBILITY_CHECKSUM/d' | awk '/#checksumstart/,/#checksumstop/' | md5sum | cut -d' ' -f1`
OLD_CHECKSUM_FILE=${DATADIR}/checksum
OLD_CHECKSUM=`touch ${OLD_CHECKSUM_FILE} ; cat ${OLD_CHECKSUM_FILE}`

if [ -f ${DATADIR}/version ] ; then
	rm ${DATADIR}/version
	OLD_CHECKSUM="icanhazregenerationplz"
fi


if [[ ! `echo - "$*" | grep -o "^-.[^\ ]*n\|\-n\|^-.[^\ ]*h\|\-h\|^-.[^\ ]*i\|-i"` ]] ; then
	if [ ! -z ${OLD_CHECKSUM} ] ; then
		if [[ ${OLD_CHECKSUM} == ${COMPATIBILITY_CHECKSUM} ]] ; then
			:
		else
			if [[ `echo "$*" | grep -o "^-.[^\ ]*c\|\-c"` ]] ; then
				echo "Logfile generation has changed!"
				echo "To avoid incompatibility, the log is now regenerated!"
			else
				echo -e "${RED}Logfile generation has changed!${NC}"
				echo -e "${RED}To avoid incompatibility, the log is now regenerated!${NC}"
			fi
			rm ${LOGNOW} ${LOG}
			echo "${COMPATIBILITY_CHECKSUM}" > ${OLD_CHECKSUM_FILE}
		fi
	else
		echo "${COMPATIBILITY_CHECKSUM}" > ${OLD_CHECKSUM_FILE}
	fi
fi

# create empty logfile if non exists
if [ ! -f ${LOGNOW} ] ; then
	touch ${LOGNOW}
fi



# timer functions

timestart()
{
	TSG=`date +%s.%N`
}

timeend()
{
	TEG=`date +%s.%N`
	TDG=`calc -p $TEG - $TSG`
}


makelog_pre() {

		# check if pacman is currently in use
	if [ -f "/var/lib/pacman/db.lck" ] ; then
		echo "ERROR, pacman is currently in use, please wait and re-run when pacman is done." >&2
		exit_ 3
	fi

	# check if we have a pacman logfile
	if [ ! -f "${PACMANLOG}" ] ; then
		echo "ERROR, could not find ${PACMANLOG}, exiting..."
		exit_ 4
	fi

	# start the timer
	timestart

	# copy the pacman log as pacman_tmp.log to our datadir
	cp ${PACMANLOG} ${DATADIR}/pacman_tmp.log

	echo -e "Getting diff between ${WHITEUL}${PACMANLOG}${NC} and an older local copy."
	# we only want to proceed new entries, old ones are already included in the log
	diff -u ${LOGNOW} ${PACMANLOG} | awk /'^+'/ | sed -e 's/^+//' > ${DATADIR}/process.log


	######################
	# core of the script #
	######################


	# get lines and size of the pacman log
	ORIGSIZE=`du -b ${DATADIR}/process.log | cut  -f1`
	ORIGLINES=`wc ${DATADIR}/process.log -l | cut -d' ' -f1`

	ORIGSIZE_OUT=`sizecalc ${ORIGSIZE}`

#checksumstart

	echo -e "Purging the diff (${ORIGLINES} lines, ${ORIGSIZE_OUT}) and saving the result to ${WHITEUL}${DATADIR}${NC}."
	sed -e 's/\ \[.*\]//'  -e 's/\[/\n[/g' -e '/^$/d' ${DATADIR}/process.log | awk '/] installed|] upgraded|] removed/' > ${LOGTOBEPROCESSED}

	PURGEDONESIZE=`du -b ${LOGTOBEPROCESSED} | cut -f1`

	PURGEDONESIZE_OUT=`sizecalc ${PURGEDONESIZE}`

	CURLINE=1
	LINEPRCOUT=1
	MAXLINES=`wc -l ${LOGTOBEPROCESSED} | cut -d' ' -f1`
	PURGELINEPERC=`calc -p "${MAXLINES}/${ORIGLINES}*100-100"`
	echo -e "Processing ${MAXLINES} lines of purged log (${PURGEDONESIZE_OUT})..."

	if [ ! ${MAXLINES} == "0" ] ; then
		echo -e "Purging efficiency: ${PURGELINEPERC:1:5}% \n"  | sed s/\ -/\ /
	else
		echo ""
	fi

	cp ${LOGTOBEPROCESSED} ${DATADIR}/tmp
	} # makelog_pre

makelog_quiet() {

		########################
		## processing the log ##
		########################


		while read line ; do
#checksumstart
			# the unix time string
			linearray=(${line})

			#UNIXDATE="${line2[1]:1:16}"
			UNIXDATE=`date +"%s" -d "${line:1:16}"`
			# put  installed/removed/upgraded information in there again, we translated these later with sed in one rush
			STATE="${linearray[2]}"
			# package name
			PKG="${linearray[3]}"

			case ${PKG} in
				lib*)
					case ${PKG} in
					libreoffice*)
						case ${PKG} in
							*extension*)
								PKG="libreoffice/extension/${PKG}.libreoffice|18A303"
								;;
							*)
								PKG="libreoffice/${PKG}.libreoffice|18A303"
								;;
						esac
						;;
					*32*)
						PKG="lib/32/${PKG}.lib|585858"
						;;
					*)
						PKG="lib/${PKG}.lib|585858"
						;;
					esac
					;;
				*xorg*)
					PKG="xorg/${PKG}.xorg|ED541C"
					;;
				*ttf*)
					PKG="ttf/${PKG}.ttf|000000"
					;;
				*xfce*)
					case ${PKG} in
						*plugin*)
							PKG="xfce/plugins/${PKG}.xfce|00CED1"
							;;
						*)
							PKG="xfce/${PKG}.xfce|00CED1"
							;;
					esac
					;;
				*sdl*)
					PKG="sdl/${PKG}.sdl|E0FFFF"
					;;
				*xf86*)
					PKG="xorg/xf86/${PKG}.xorg|ED541C"
					;;
				*perl*)
					PKG="perl/${PKG}.perl|FF0000"
					;;
				*gnome*)
					PKG="gnome/${PKG}.gnome|5C3317"
					;;
				*gtk*)
					PKG="gtk/${PKG}.gtk|FFFF00"
					;;
				*gstreamer*)
					PKG="gstreamer/${PKG}.gstreamer|FFFF66"
					;;
				*kde*)
					case ${PKG} in
						*kdegames*)
							PKG="kde/games/${PKG}.kde|0000CC"
							;;
						*kdeaccessibility*)
							PKG="kde/accessebility/${PKG}.kde|0000CC"
							;;
						*kdeadmin*)
							PKG="kde/admin/${PKG}.kde|0000CC"
							;;
						*kdeartwork*)
							PKG="kde/artwork/${PKG}.kde|0000CC"
							;;
						*kdebase*)
							PKG="kde/base/${PKG}.kde|0000CC"
							;;
						*kdeedu*)
							PKG="kde/edu/${PKG}.kde|0000CC"
							;;
						*kdegames*)
							PKG="kde/games/${PKG}.kde|0000CC"
							;;
						*kdegraphics*)
							PKG="kde/graphics/${PKG}.kde|0000CC"
							;;
						*kdemultimedia*)
							PKG="kde/multimedia/${PKG}.kde|0000CC"
							;;
						*kdenetwork*)
							PKG="kde/network/${PKG}.kde|0000CC"
							;;
						*kdepim*)
							PKG="kde/pim/${PKG}.kde|0000CC"
							;;
						*kdeplasma*)
							PKG="kde/plasma/${PKG}.kde|0000CC"
							;;
						*kdesdk*)
							PKG="kde/sdk/${PKG}.kde|0000CC"
							;;
						*kdetoys*)
							PKG="kde/toys/${PKG}.kde|0000CC"
							;;
						*kdeutils*)
							PKG="kde/utils/${PKG}.kde|0000CC"
							;;
						*kdewebdev*)
							PKG="kde/webdev/${PKG}.kde|0000CC"
							;;
						*)
							PKG="kde/${PKG}.kde|0000CC"
							;;
					esac
					;;
				*python*|py*)
					PKG="python/${PKG}.python|2F4F4F"
					;;
				*lxde*|lx*)
					PKG="lxde/${PKG}.lxde|8C8C8C"
					;;
				*php*)
					PKG="php/${PKG}.php|6C7EB7"
					;;
				vim*)
					PKG="vim/${PKG}.vim|00FF66"
					;;
				*texlive*)
					PKG="texlive/${PKG}.texlive|660066"
					;;
				*alsa*)
					PKG="alsa/${PKG}.alsa|C8DEC9"
					;;
				*compiz*)
					PKG="compiz/${PKG}.compiz|FF0066"
					;;
				*dbus*)
					PKG="dbus/${PKG}.dbus|99FFFF"
					;;
				gambas*)
					case ${PKG} in
						gambas2*)
							PKG="gambas/2/${PKG}.gambas|996633"
							;;
						gambas3*)
							PKG="gambas/3/{PKG}.gambas|996633"
							;;
						*)
							PKG="gambas/${PKG}.gambas|996633"
							;;
					esac
					;;
				*qt*)
					PKG="qt/${PKG}.qt|91219E"
					;;
				*firefox*|*thunderbird*|*seamonky*)
					PKG="mozilla/${PKG}.mozilla|996633"
					;;
				*)
			esac

			#    this is an awful hack to get the vars via multitasking, but it works :)
			echo "$UNIXDATE" > /dev/null &
			echo "$STATE" > /dev/null &
			echo "$PKG" > /dev/null &
			wait


			#    write the important stuff into our logfile
			echo "${UNIXDATE}|root|${STATE}|${PKG}" >> ${DATADIR}/pacman_gource_tree.log
		done < ${DATADIR}/tmp
} # makelog_quiet


makelog() {

	while [ "$CURLINE" -le "$MAXLINES" ]; do
		########################
		## processing the log ##
		########################

		# to read the file via loop
		IFS=$'\n'
		set -f
		for i in $(<${DATADIR}/tmp); do
			# the unix time string
			UNIXDATE=`date +"%s" -d "${i:1:16}"`
			# put  installed/removed/upgraded information in there again, we translated these later with sed in one rush
			STATE=`cut -d' ' -f3 <( echo ${i} )`
			# package name
			PKG=`cut -d' ' -f4  <( echo ${i} )`

			case ${PKG} in
				lib*)
					case ${PKG} in
					libreoffice*)
						case ${PKG} in
							*extension*)
								PKG="libreoffice/extension/${PKG}.libreoffice|18A303"
								;;
							*)
								PKG="libreoffice/${PKG}.libreoffice|18A303"
								;;
						esac
						;;
					*32*)
						PKG="lib/32/${PKG}.lib|585858"
						;;
					*)
						PKG="lib/${PKG}.lib|585858"
						;;
					esac
					;;
				*xorg*)
					PKG="xorg/${PKG}.xorg|ED541C"
					;;
				*ttf*)
					PKG="ttf/${PKG}.ttf|000000"
					;;
				*xfce*)
					case ${PKG} in
						*plugin*)
							PKG="xfce/plugins/${PKG}.xfce|00CED1"
							;;
						*)
							PKG="xfce/${PKG}.xfce|00CED1"
							;;
					esac
					;;
				*sdl*)
					PKG="sdl/${PKG}.sdl|E0FFFF"
					;;
				*xf86*)
					PKG="xorg/xf86/${PKG}.xorg|ED541C"
					;;
				*perl*)
					PKG="perl/${PKG}.perl|FF0000"
					;;
				*gnome*)
					PKG="gnome/${PKG}.gnome|5C3317"
					;;
				*gtk*)
					PKG="gtk/${PKG}.gtk|FFFF00"
					;;
				*gstreamer*)
					PKG="gstreamer/${PKG}.gstreamer|FFFF66"
					;;
				*kde*)
					case ${PKG} in
						*kdegames*)
							PKG="kde/games/${PKG}.kde|0000CC"
							;;
						*kdeaccessibility*)
							PKG="kde/accessebility/${PKG}.kde|0000CC"
							;;
						*kdeadmin*)
							PKG="kde/admin/${PKG}.kde|0000CC"
							;;
						*kdeartwork*)
							PKG="kde/artwork/${PKG}.kde|0000CC"
							;;
						*kdebase*)
							PKG="kde/base/${PKG}.kde|0000CC"
							;;
						*kdeedu*)
							PKG="kde/edu/${PKG}.kde|0000CC"
							;;
						*kdegames*)
							PKG="kde/games/${PKG}.kde|0000CC"
							;;
						*kdegraphics*)
							PKG="kde/graphics/${PKG}.kde|0000CC"
							;;
						*kdemultimedia*)
							PKG="kde/multimedia/${PKG}.kde|0000CC"
							;;
						*kdenetwork*)
							PKG="kde/network/${PKG}.kde|0000CC"
							;;
						*kdepim*)
							PKG="kde/pim/${PKG}.kde|0000CC"
							;;
						*kdeplasma*)
							PKG="kde/plasma/${PKG}.kde|0000CC"
							;;
						*kdesdk*)
							PKG="kde/sdk/${PKG}.kde|0000CC"
							;;
						*kdetoys*)
							PKG="kde/toys/${PKG}.kde|0000CC"
							;;
						*kdeutils*)
							PKG="kde/utils/${PKG}.kde|0000CC"
							;;
						*kdewebdev*)
							PKG="kde/webdev/${PKG}.kde|0000CC"
							;;
						*)
							PKG="kde/${PKG}.kde|0000CC"
							;;
					esac
					;;
				*python*|py*)
					PKG="python/${PKG}.python|2F4F4F"
					;;
				*lxde*|lx*)
					PKG="lxde/${PKG}.lxde|8C8C8C"
					;;
				*php*)
					PKG="php/${PKG}.php|6C7EB7"
					;;
				vim*)
					PKG="vim/${PKG}.vim|00FF66"
					;;
				*texlive*)
					PKG="texlive/${PKG}.texlive|660066"
					;;
				*alsa*)
					PKG="alsa/${PKG}.alsa|C8DEC9"
					;;
				*compiz*)
					PKG="compiz/${PKG}.compiz|FF0066"
					;;
				*dbus*)
					PKG="dbus/${PKG}.dbus|99FFFF"
					;;
				gambas*)
					case ${PKG} in
						gambas2*)
							PKG="gambas/2/${PKG}.gambas|996633"
							;;
						gambas3*)
							PKG="gambas/3/{PKG}.gambas|996633"
							;;
						*)
							PKG="gambas/${PKG}.gambas|996633"
							;;
					esac
					;;
				*qt*)
					PKG="qt/${PKG}.qt|91219E"
					;;
				*firefox*|*thunderbird*|*seamonky*)
					PKG="mozilla/${PKG}.mozilla|996633"
					;;
				*)
			esac

			#    this is an awful hack to get the vars via multitasking, but it works :)
			echo "$UNIXDATE" > /dev/null &
			echo "$STATE" > /dev/null &
			echo "$PKG" > /dev/null &
			wait


			#    write the important stuff into our logfile
			echo "${UNIXDATE}|root|${STATE}|${PKG}" >> ${DATADIR}/pacman_gource_tree.log
#checksumstop
			#    here we print how log the script already took to run and try to estimate how log it will run until everything is done
			#    but we only update this every 1000 lines to avoid unnecessary stdout spamming
			#    this will mostly be printed when initially obtaining the log
			if [ "${LINEPERCOUT}" == "1000" ] ; then
				LINECOUNTCOOKIE=1
				#    can we use  expr  here, or something more simple?
				LINEPERC=`calc -p "${CURLINE} / ${MAXLINES} *100" | sed -e 's/\~//'`
				timeend
				#    same as echo ${TDG} | grep -o "[0-9]*\.\?[0-9]\?[0-9]" # | head -n1
				TGDOUT=`awk 'match($0,/[0-9]*.?[0-9]?[0-9]/) {print substr($0,RSTART,RLENGTH)}' <( echo "${TDG}")`
				TIMEDONEONE=`calc -p "100 / ${LINEPERC:0:4} *${TDG}" | sed 's/\~//'`
				TIMEDONEFINAL=`calc -p "${TIMEDONEONE} - ${TDG}" | sed 's/\~//' | awk 'match($0,/[0-9]*.?[0-9]?[0-9]/) {print substr($0,RSTART,RLENGTH)}'`
				echo "Already ${LINEPERC:0:4}% done after ${TGDOUT}s."
				echo -e "Done in approximately ${TIMEDONEFINAL}s.\n"
				LINEPERCOUT=0
			fi
			#     switch to next line and re-start the loop
			let CURLINE=${CURLINE}+1
			let LINEPERCOUT=${LINEPERCOUT}+1
		done
		# file loop stuff..
		set +f
		unset IFS
	done

} # makelog


makelog_post() {

	# was the package installed/removed/upgraded?  here we actually translate this important information
	sed -e 's/|installed|/|A|/' -e 's/|upgraded|/|M|/' -e 's/|removed|/|D|/' ${DATADIR}/pacman_gource_tree.log > ${DATADIR}/tmp2.log
	mv ${DATADIR}/tmp2.log ${DATADIR}/pacman_gource_tree.log &
	mv ${DATADIR}/pacman_tmp.log ${LOGNOW} &
	rm ${DATADIR}/pacman_purged.log ${DATADIR}/process.log ${DATADIR}/tmp &
	wait

	# take the existing log and remove the paths so we have our pie-like log again which I had at the beginning of the developmen process of this script :)
	# yes, this may look stupid, first writing a package category and then removing it afterwards, but I think its faster to edit the entire file in one rush
	# instead of writing every single line into a file
	sed -e 's/D|.*\//D\|/' -e 's/M|.*\//M\|/' -e 's/A|.*\//A\|/' ${DATADIR}/pacman_gource_tree.log  > ${DATADIR}/pacman_gource_pie.log


	# how log did the script take to run?
	timeend

	if [[ ${LINECOUNTCOOKIE} == "1" ]] ; then
		TIMEFINAL=`awk 'match($0,/[0-9]*\.?[0-9]?[0-9]/) {print substr($0,RSTART,RLENGTH)}' <( echo "${TDG}" )`
	else
		TIMEFINAL=`awk 'match($0,/[0-9]*.[0-9]{5}/) {print substr($0,RSTART,RLENGTH)}' <( echo "${TDG}" )`
	fi

	if [[ ${MAXLINES} == "0" ]] ; then
		LINESPERSEC="0"
	else
		LINESPERSEC=`calc -p "${MAXLINES}/${TIMEFINAL}"`
	fi

	echo -e "100 % done after ${RED}${TIMEFINAL}${NC}s."
	echo -e "${RED}${LINESPERSEC:0:6}${NC} lines per second.\n"

	rm ${DATADIR}/lock # remove lockfile
} # makelog_post


help() {
	echo -e "-n  do${WHITEUL}N${NC}'t update the log"
	echo -e "-c  don't use ${WHITEUL}C${NC}olors for shell output"
	echo -e "-g  start ${WHITEUL}G${NC}ource afterwards"
	echo -e "-f  capture the video using ${WHITEUL}F${NC}fmpeg"
	echo -e "-p  makes use of -g and uses ${WHITEUL}P${NC}ie log"
	echo -e "-a  skip ${WHITEUL}A${NC}rchitecture in title"
	echo -e "-o  skip h${WHITEUL}O${NC}stname in title"
	echo -e "-t  skip ${WHITEUL}T${NC}imestaps in title"
	echo -e "-i  show some ${WHITEUL}I${NC}nformation regarding pacmanlog2gource"
	echo -e "-m  skip package na${WHITEUL}M${NC}es"
	echo -e "-l  show ${WHITEUL}icon${NC} in lower right corner"
	echo -e "-L  show ${WHITEUL}logo${NC} in lower right corner"
	echo -e "-q  don't estimate when log conversion is finished, and be faster"
	echo -e "-d  show ${WHITEUL}D${NC}ebug information (set -x)"
	echo -e "-h  show this ${WHITEUL}H${NC}elp"
}

logbeginningdate=`head -n1 ${LOGNOW} |  cut -d' ' -f1 | sed  -e 's/\[//'`
logbeginning=`date +"%d %b %Y" -d "${logbeginningdate}"`

logenddate=`tail -n1 ${LOGNOW} | cut -d' ' -f1 | sed  -e 's/\[//'`
logend=`date +"%d %b %Y" -d "${logenddate}"`

cpucores=`getconf _NPROCESSORS_ONLN`

gourcebinarypath=`whereis gource | cut -d' ' -f2`
gourcename_version=`pacman -Qo ${gourcebinarypath} | cut -d' ' -f"5 6"`

LOGTIMES=", ${logbeginning} - ${logend}"
HOSTNAME=", hostname: `hostname`"
ARCH=", `uname -m`"


while getopts "nchgfpaotimdlLq" opt; do
	case "$opt" in
		"n")
			echo "Log not updated." >&2
			UPDATE="false"
			;;
		"c")
			RED=''
			GREEN=''
			GREENUL=''
			WHITEUL=''
			NC=''
			echo "Skipping colors in output."
			echo "NOTE: this won't affect stdout of gource or ffmpeg."
			;;
		"h")
			UPDATE="false"
			help
			exit_ 0
			;;
		"g")
			GOURCEPOST="true"
			;;
		"f")
			FFMPEGPOST="true"
			GOURCEPOST="true"
			;;
		"p")
			LOG=${DATADIR}/pacman_gource_pie.log
			GOURCEPOST="true"
			;;
		"a")
			ARCH=''
			;;
		"o")
			HOSTNAME=''
			;;
		"t")
			LOGTIMES=''
			;;
		"i")
			UPDATE="false"
			INFORMATION="true"
			;;
		"m")
			FILENAMES=",filenames"
			GOURCEPOST="true"
			echo "Filenames will be skipped in the video." >&2
			;;
		"l")
		GOURCEPOST=true
		LOGOIMAGE="--logo ${DATADIR}/archlinux-icon-crystal-64.png"
		if [ ! -f ${DATADIR}/archlinux-icon-crystal-64.png ] ; then
			if [ -f /usr/share/archlinux/icons/archlinux-icon-crystal-64.svg ] ; then # if we don't have the icon locally...
				echo -e "${RED}Icon found locally, converting...${NC}"
				convert -background none /usr/share/archlinux/icons/archlinux-icon-crystal-64.svg ${DATADIR}/archlinux-icon-crystal-64.png
			else # ....download it
				echo -e "${RED}Icon not found locally, downloading icons...${NC}"
				mkdir ${DATADIR}/tmp
				cd ${DATADIR}/tmp
				wget --continue "ftp://ftp.archlinux.org/other/artwork/archlinux-artwork-1.6.tar.gz" ./archlinux-artwork-1.6.tar.gz || echo -e "${RED}Could not download file, no image will be displayed.${NC}" ; LOGOIMAGE=" "
				echo -e "${RED}Extracting archive....${NC}"
				tar -zxvf archlinux-artwork-1.6.tar.gz
				echo -e "${RED}Converting icon...${NC}"
				convert -background none ./archlinux-artwork-1.6/icons/archlinux-icon-crystal-64.svg ../archlinux-icon-crystal-64.png
				cd ../
				echo -e "${RED}Removing unwanted files...${NC}"
				rm -rf ./tmp
			fi
			echo -e "${RED}Done${NC}"
		fi
		;;
		"L")
		GOURCEPOST=true
		LOGOIMAGE="--logo ${DATADIR}/archlogo.png"
		if [ ! -f ${DATADIR}/archlogo.png ] ; then
				echo -e "${RED}Logo not found locally, downloading...${NC}"
				cd ${DATADIR}
				wget --continue "http://www.archlinux.org/static/archnavbar/archlogo.png"  || echo -e "${RED}Could not download file, no image will be displayed.${NC}" ; LOGOIMAGE=" "
				echo -e "${RED}Done${NC}"
		fi
		;;
		"d")
		#	DEBUG="true"
		#	echo "Entering debug mode..." >&2
			;;
		"q")
			QUIET="true"
			echo "Entering quiet mode, this should be faster than default mode"
			echo "but doesn't estimate when log genration will be finished."
			;;
		"?")
			UPDATE="false"
			echo "Pacmanlog2gource: invalid option!" >&2
			echo "Please try  pacmanlog2gource -h  for possible options." >&2
			exit_ 1
			;;
		*)
			echo "Pacmanlog2gource: unknown error while processing options." >&2
			exit_ 1
			;;
	esac
done

	TITLE="Pacmanlog2gource${LOGTIMES}${HOSTNAME}${ARCH}"

if [ ${INFORMATION} == "true" ] ; then
	if [ "$*" == "-i" ] ; then
		ARGS=""
	else
		ARGS="`sed -e 's/i//' <( echo "${*}" )` "
	fi
	echo -e "The command which will be run using ${GREEN}pacmanlog2gource ${ARGS}${NC}is"
	if [ ${FFMPEGPOST} != "true" ] ; then
		echo -e "${GREEN}gource ${GREENUL}${DATADIR}/pacman_gource_tree.log${NC}${GREEN} -1200x720 -c 1.1 --title \"${TITLE}\" --key --camera-mode overview --highlight-all-users --file-idle-time 0 -auto-skip-seconds 0.001 --seconds-per-day 0.3 --hide progress,mouse${FILENAMES} --stop-at-end --max-files 99999999999 --max-file-lag 0.00001  --max-user-speed 300 --user-friction 2 ${LOGOIMAGE} --bloom-multiplier 1.3 ${NC}"
	else
		echo -e "${GREEN}gource ${GREENUL}${DATADIR}/pacman_gource_tree.log${NC}${GREEN} -1200x720 -c 1.1 --title \"${TITLE}\" --key --camera-mode overview --highlight-all-users --file-idle-time 0 -auto-skip-seconds 0.001 --seconds-per-day 0.3 --hide progress,mouse${FILENAMES} --stop-at-end --max-files 99999999999 --max-file-lag 0.00001  --max-user-speed 300 --user-friction 2 ${LOGOIMAGE} --bloom-multiplier 1.3 --output-ppm-stream - | ffmpeg -f image2pipe -vcodec ppm -i - -y -vcodec libx264 -preset medium -crf 22 -pix_fmt yuv420p -threads ${cpucores} -b:v 3000k -maxrate 8000k -bufsize 10000k ${GREENUL}pacmanlog2gource_`date +%b\_%d\_%Y`.mp4${NC}"
	fi
	echo -e "Logfiles are stored in ${WHITEUL}${DATADIR}/pacman_gource_tree.log${NC} and ${WHITEUL}${DATADIR}/pacman_gource_pie.log${NC}."
	echo -e "Pacmanlog2gource version: ${VERSION}"
	echo -e "Gource version: ${gourcename_version}"
	echo "Feel free to comment https://bbs.archlinux.org/viewtopic.php?pid=1105145"
	echo "or fork https://github.com/matthiaskrgr/pacmanlog2gource"
	exit_ 0
fi

if [ ${UPDATE} == "true" ] ; then
	makelog_pre
	if [ ${QUIET} == "true" ] ; then
		makelog_quiet
	else
		makelog
	fi
	makelog_post

	echo -e "Output files are ${WHITEUL}${DATADIR}/pacman_gource_tree.log${NC}"
	echo -e "\t and ${WHITEUL}${DATADIR}/pacman_gource_pie.log${NC}.\n\n"
fi

if [ ${GOURCEPOST} == "true" ] ; then
	if [ ${FFMPEGPOST} == "true" ] ; then
	echo -e "<output of ${GREEN}ffmpeg${NC}>"
		gource ${LOG} -1200x720  -c 1.1 --title "${TITLE}" --key --camera-mode overview --highlight-all-users --file-idle-time 0 -auto-skip-seconds 0.001 --seconds-per-day 0.3 --hide progress,mouse${FILENAMES} --stop-at-end --max-files 99999999999 --max-file-lag 0.00001  --max-user-speed 300 --user-friction 2 ${LOGOIMAGE} --bloom-multiplier 1.3 --output-ppm-stream - | ffmpeg -f image2pipe -vcodec ppm -i - -y -vcodec libx264 -preset medium -crf 22 -pix_fmt yuv420p -threads ${cpucores} -b:v 3000k -maxrate 8000k -bufsize 10000k pacmanlog2gource_`date +%b\_%d\_%Y`.mp4
	echo -e "</output of  ${GREEN}ffmpeg${NC}>"
	else
		echo -e "To record the video to a mp4 file using ffmpeg, run  ${GREEN}pacmanlog2gource -f${NC}  ."
		gource ${LOG} -1200x720  -c 1.1 --title "${TITLE}" --key --camera-mode overview --highlight-all-users --file-idle-time 0 -auto-skip-seconds 0.001 --seconds-per-day 0.3 --hide progress,mouse${FILENAMES} --stop-at-end --max-files 99999999999 --max-file-lag 0.00001  --max-user-speed 300 --user-friction 2 ${LOGOIMAGE} --bloom-multiplier 1.3
	fi
else
	echo -e "To visualize the log, run  ${GREEN}pacmanlog2gource -g${NC}"
fi

echo -e "For more information run ${GREEN}pacmanlog2gource -i${NC} or ${GREEN}pacmanlog2gource -h${NC}"
echo "Thanks for using pacmanlog2gource!"
exit_ 0
