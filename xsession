#!/bin/bash
# Single Xwindow/KDE startup script
# (C) Klaus Knopper Jun 2001
# (C) 2005, 2006 modified by Stefan Lippers-Hollmann <s.l-h@gmx.de>

# override tool behaviour through distro-defaults
FLL_DISTRO_MODE="installed"
FLL_LIVE_USER="sidux"
if [ -r /etc/default/distro ]; then
        . /etc/default/distro
fi

# don't ever start me on an installed system
[ ! "$FLL_DISTRO_MODE" = "live" ] && exit 0

XSERVER="Xorg"
X_CONF="/etc/X11/xorg.conf"
HWSETUP_XSERVER="/etc/sysconfig/xserver"
HWSETUP_MAIN="/etc/sysconfig/knoppix"
XSESSION_COMMANDS="/etc/sysconfig/xsession-commands"
XSESSION_RESTART="/etc/sysconfig/xsession-restart"

PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin"
export PATH

umask 022

CRE="
[K"
BLUE="[1;34m"
NORMAL="[1;39m"

RUNLEVEL5=""
case "$(runlevel)" in
	*\ 5)
		RUNLEVEL5="true"
		;;
esac

XMODULE=""
[ -f "$HWSETUP_XSERVER" ] &&	source "$HWSETUP_XSERVER"
[ -f "$HWSETUP_MAIN" ] &&	source "$HWSETUP_MAIN"

[ -n "$BACKGROUND" -a -e "$BACKGROUND" ] || BACKGROUND="-solid black"

# Disable TCP listening
NOLISTEN="-nolisten tcp"

# Black
BR="-br"

SOCKET_DIR=/tmp/.X11-unix
ICE_DIR=/tmp/.ICE-unix
mkdir -p $SOCKET_DIR
chown 0:0 $SOCKET_DIR
chmod 1777 $SOCKET_DIR
mkdir -p $ICE_DIR
chown 0:0 $ICE_DIR
chmod 1777 $ICE_DIR

# See how we were called.
case "$1" in
	start)
		rm -f "$XSESSION_RESTART"
		# Don't start X if brltty is running!
		BPID="$(pidof brltty 2>/dev/null)"
		[ "$?" = "0" ] && exit 0

		echo "${CRE}${BLUE}Executing $0 $1:${NORMAL}"
		
		# Start daemons.
		REALMEM="$(cat /proc/meminfo | awk '/MemTotal/{print $2}')"
		if [ -n "$REALMEM" -a "$REALMEM" -lt 14000 ]; then
			echo "${BLUE}$0: ${RED}Sorry, You need at least 16 Megs of RAM to start the X-Window system.${NORMAL}"
			echo "${BLUE}$0: ${RED}Exiting now.${NORMAL}"
			exit 1
		fi

		echo ""
		echo "	${NORMAL}Starting single X-Window session for User $FLL_LIVE_USER."
		echo "	Please stand by a few seconds while the optimal configuration"
		echo "	is being determined."
		
		if [ -n "$RUNLEVEL5" ]; then
			echo ""
			echo "After this session terminates, the system will automatically shut down."
		fi
		
		echo ""
		echo -n "${BLUE}Starting X11...${NORMAL}"

		ACCEL=""
		XOPTIONS=""
		DPI="-dpi 72"
		[ -n "$CUSTOM_DPI" ] && DPI="-dpi $CUSTOM_DPI"
		[ "$CUSTOM_DPI" = "auto" ] && DPI=""
		NORESET=""
		[ -n "$XSERVER" -a -x "/usr/bin/$XSERVER" ] && ACCEL="$XSERVER"
		[ -L /etc/X11/X ] && ACCEL="$ACCEL /etc/X11/X"
		
		# hack i810 vga modes
		if [ -z "$NO915RES" -a "$XMODULE" = "i810" -a -x /usr/sbin/915resolution ]; then
			if [[ $(915resolution -l 2>/dev/null) != *$XSCREEN* ]]; then
				915resolution 5c ${XSCREEN/x*} ${XSCREEN#*x} &>/dev/null
				
				mkdir -p /etc/default/
				rm -f /etc/default/915resolution
				cat > /etc/default/915resolution <<EOF
#
# 915resolution default
#
# find free modes by  /usr/sbin/915resolution -l
# and set it to MODE
#
MODE=5c

#
# and set resolutions for the mode.
#
XRESO=${XSCREEN/x*}
YRESO=${XSCREEN#*x}
EOF
			fi
		fi

		# Try to find and load an agp and drm module for this graphics card
		case "$(cat /proc/cmdline)" in
			*noagp*)
				;;
			*)
				for i in /lib/modules/$(uname -r)/kernel/drivers/char/agp/*; do
					module="${i##*/}"; module="${module%%.*}"
					modprobe ${module} >/dev/null 2>&1
				done

				# remove unused agp modules
				for module in $(awk '/_agp/{if ($3==0) print $1}' /proc/modules); do
					rmmod $module 2>/dev/null
				done
				;;
		esac

		if [ -n "$XMODULE" ]; then
			# All kernels: Load drm module
			for i in /lib/modules/$(uname -r)/kernel/drivers/char/drm/*; do
				case "$i" in
					*$XMODULE*)
						module="${i##*/}"
						module="${module%%.*}"
						modprobe ${module} >/dev/null 2>&1
						;;
				esac
			done
		fi

		for X in $ACCEL vesa fbdev; do
			BPP="-bpp"
			
			case "$X" in
				*Xorg*)
					BPP="-depth"
					NORESET="-noreset"
					;;
				vesa|fbdev)
					echo "XMODULE=\"$X\"" >> "$HWSETUP_MAIN"
					echo "XMODULE=\"$X\"" >> "$HWSETUP_XSERVER"
					
					echo "${NORMAL}"
					echo -n "${BLUE}Retrying with Server ${GREEN}${XSERVER}(${YELLOW}$X${GREEN})${NORMAL} "
					rm -f "$X_CONF"
					mkxf86config >/dev/null 2>&1
					
					X=Xorg
					BPP="-depth"
					NORESET="-noreset"
					XOPTIONS=""
					;;
			esac

			# Try hwsetup-generated flags first, if present
			$X $NOLISTEN $NORESET -xf86config "$X_CONF" $XOPTIONS $DPI $BR :0 2>/dev/null && break
			
			# Mostly failsafe probe fallbacks
			# Some cards prefer 16 bit, especially when low on mem or not SVGA,
			# so try this first.
			if $X $NOLISTEN $NORESET -xf86config "$X_CONF" $BPP 16 $DPI $BR :0 2>/dev/null || \
			   $X $NOLISTEN $NORESET -xf86config "$X_CONF" $BPP 24 $DPI $BR :0 2>/dev/null || \
			   $X $NOLISTEN $NORESET -xf86config "$X_CONF" $BPP  8 $DPI $BR :0 2>/dev/null; then
				break
			fi
			
			echo -n "${BLUE}.${NORMAL}"
		done &
		
		sleep 2

		# Wait for X-Server startup
		for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
			found="true"
			
			# Startup Logo
			# DISPLAY=:0 xloadimage -center -onroot -border black \
			DISPLAY=:0 xloadimage -onroot -fullscreen -shrink -smooth -border black -quiet $BACKGROUND >/dev/null 2>&1 && break
			found="false"
			sleep 1
		done
		
		echo ""

		if [ "$found" = "false" ]; then
			echo "${RED}Error: No suitable X-Server found for your card.${NORMAL}"
			exit 1
		fi

		# FIXME: Move to others
		rm -f "$XSESSION_COMMANDS"
		touch "$XSESSION_COMMANDS"
		chown $FLL_LIVE_USER:$FLL_LIVE_USER "$XSESSION_COMMANDS"

		su -c "DISPLAY=:0 exec /bin/sh /etc/X11/xinit/xinitrc" - $FLL_LIVE_USER >/dev/null 2>&1
		RC="$?"

		XSESSION_COMMAND=$(cat "$XSESSION_COMMANDS") # Read in what kde / ... told us.

		# After xsession exits, end X-Server
		for i in $ACCEL $X $XSERVER Xorg; do
			killall -TERM "$i" 2>/dev/null && break
		done
		
		echo ""
		echo -n "${CRE}${BLUE}X-Window session terminated "
		if [ "$RC" = "0" ]; then
			echo "without errors."
			NEXT_RUNLEVEL=0

			if [ -n "$XSESSION_COMMAND" ]; then
				case "$XSESSION_COMMAND" in
					shutdown*halt*)
						NEXT_RUNLEVEL=0
						;;
					shutdown*reboot*)
						NEXT_RUNLEVEL=6
						;;
					kde_restart)
						[ ! -f "$XSESSION_RESTART" ] && exec $0 start
						;;
				esac
			fi

			if [ -n "$RUNLEVEL5" -a ! -f "$XSESSION_RESTART" ]; then
				echo "Shutting down.${NORMAL}"
				# Play informational sound if soundcore module present
				# (checking /dev/sndstat is unreliable)
				OGGPLAY=/usr/bin/ogg123
				PLAY=/usr/bin/wavp
				[ -x "$PLAY" ] || PLAY=/usr/bin/play-sample
				[ -x "$PLAY" ] || PLAY=/usr/bin/play
			
				if [ -x "$OGGPLAY" -a -f /usr/share/sounds/shutdown.ogg ]; then
					case "$(lsmod)" in
						*sound*)
							$OGGPLAY -q -p 64 /usr/share/sounds/shutdown.ogg >/dev/null 2>&1 & 
							sleep 7
							;;
					esac
				elif [ -f /usr/share/sounds/shutdown.wav -a -x "$PLAY" ]; then
					case "$(lsmod)" in
						*sound*)
							$PLAY /usr/share/sounds/shutdown.wav >/dev/null 2>&1 & 
							sleep 7
							;;
					esac
				fi

				init $NEXT_RUNLEVEL
			fi
		else
			echo "with errors."
			echo "${RED}Please check $X_CONF and retry ${CYAN}'$0 start'${RED}.${NORMAL}"
		fi
	        ;;
	stop)
		# Stop daemons.
		# Don't shutdown if killed by init or manually
		touch "$XSESSION_RESTART"
		
		for i in $XSERVER XF86_SVGA; do
			killall -TERM "$i" 2>/dev/null && echo "${BLUE}X-Server shut down.${NORMAL}" && break
		done
		;;
	restart)
		touch "$XSESSION_RESTART"
		( nohup bash -c "$0 stop; sleep 5; $0 start" & )
		;;
	force-reload)
		touch "$XSESSION_RESTART"
		( nohup bash -c "$0 stop; sleep 5; $0 start" & )
		;;
	*)
		echo "${RED}Usage: xsession {start|stop}${NORMAL}"
	exit 1
esac

exit 0

