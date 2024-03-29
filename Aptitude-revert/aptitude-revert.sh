#!/bin/bash

WORKDIR="$PWD/work"

if [ ! -d "$WORKDIR" ] ; then
	mkdir "$WORKDIR"
fi
cd "$WORKDIR"

if [ -f "aptitude-revert-force.log" ] ; then
	REVERT_FILE="aptitude-revert-force.log"
else
	LOGFILE_FIRST_LINE="$(grep -n "Aptitude" /var/log/aptitude | tail -1)"
	LOGFILE_FIRST_LINE_NO="$(echo $LOGFILE_FIRST_LINE | cut -d ':' -f 1)"
	LOGFILE_REVERT_TIMESTAMP="$(sed -n "$(($LOGFILE_FIRST_LINE_NO+1))p" /var/log/aptitude)"
	LOGFILE_REVERT_TIMESTAMP_ISO8601="$(date --iso-8601=seconds -d "$LOGFILE_REVERT_TIMESTAMP")"
	REVERT_FILE="aptitude-${LOGFILE_REVERT_TIMESTAMP_ISO8601}.log"

	tail -n "+${LOGFILE_FIRST_LINE_NO}" /var/log/aptitude > "$REVERT_FILE"
fi

echo -e "Using logfile \"$REVERT_FILE\"\n"

REVERT_REMOVES="$(grep REMOVE $REVERT_FILE)"
REVERT_INSTALLS="$(grep INSTALL $REVERT_FILE)"
REVERT_UPGRADES="$(grep UPGRADE $REVERT_FILE)"

if [[ $ARGC -ge 0 ]] && [ "$1" == "--norepo" ] ; then
    NO_REPO=1
else
    NO_REPO=0
fi

if [ $NO_REPO == 0 ] ; then
        echo "Evaluating usefulness of configured repos..."
        REVERT_DO_APT_INSTALL="$(sed 's/.*] \(.*\):\(.*\) \(.*\)/\1=\3/' <<< "$REVERT_REMOVES")"
        for PACKAGE in $REVERT_DO_APT_INSTALL ; do
                REVERT_DO_APT_INSTALLABLE+="$PACKAGE "
        done
        REVERT_DO_APT_REMOVE="$(sed 's/.*] \(.*\):\(.*\) \(.*\)/\1/' <<< "$REVERT_INSTALLS")"
        for PACKAGE in $REVERT_DO_APT_REMOVE ; do
                REVERT_DO_APT_REMOVABLE+="${PACKAGE}- "
        done
        REVERT_DO_APT_DOWNGRADE="$(sed 's/.*] \(.*\):\(.*\) \(.*\) ->.*/\1=\3/' <<< "$REVERT_UPGRADES")"
        for PACKAGE in $REVERT_DO_APT_DOWNGRADE ; do
                REVERT_DO_APT_DOWNGRADEABLE+="$PACKAGE "
        done
        APTITUDE_CMD_PACKAGES="$REVERT_DO_APT_INSTALLABLE $REVERT_DO_APT_REMOVABLE $REVERT_DO_APT_DOWNGRADEABLE"
        APTITUDE_CMD_SIM="aptitude install -s $APTITUDE_CMD_PACKAGES"
        APTITUDE_CMD_REAL="aptitude install $APTITUDE_CMD_PACKAGES"
        echo "$APTITUDE_CMD_SIM"
        echo "#!/bin/sh"$'\n'"$APTITUDE_CMD_REAL" > revert-repo.sh
        chmod 755 revert-repo.sh
        if $APTITUDE_CMD_SIM ; then
                echo "Able to revert with aptitude using configured repos"
                echo "Run $WORKDIR/revert-repo.sh to proceed with the revert"
                exit 0
        else
                echo -e "Unable to revert with aptitude using configured repos\n"
        fi
else
    echo -e "Argument --norepo given, skipping repo evaluation\n"
fi

echo "Trying to gather package files..."

if [ ! -d "$WORKDIR/packages" ] ; then
	mkdir "$WORKDIR/packages"
fi

cd "$WORKDIR/packages"

MISSING_FILES=""
REVERT_DO_INSTALLABLE=""
REVERT_DO_DOWNGRADEABLE=""

#FIXME Assumes the package arch is the same as the repo arch (i.e. fails for packages with arch "all")
REVERT_DO_INSTALL="$(sed 's/.*] \(.*\):\(.*\) \(.*\)/\1_\3_\2.deb/' <<< "$REVERT_REMOVES" | sed 's/:/%3a/')"
for FILE in $REVERT_DO_INSTALL ; do
	if [ ! -f "${FILE}" ] ; then
        FILE_PATH="/var/cache/apt/archives/${FILE}"
		if [ ! -f "$FILE_PATH" ] ; then
            if [ $NO_REPO == 0 ] && apt-get download $(sed 's/\([^_]*\)_\([^_]*\).*/\1=\2/' <<< "$FILE" | sed 's/%3a/:/') ; then
                echo "Downloaded  ok: $FILE"
            else
                echo "File not found: $FILE"
                MISSING_FILES+=$'\n'" $FILE"
            fi
		else
			echo "In  apt  cache: $FILE"
			cp "$FILE_PATH" "."
		fi
	else
		echo "In package dir: $FILE"
	fi
	REVERT_DO_INSTALLABLE+="$FILE "
done

#echo "$REVERT_INSTALLS"
REVERT_DO_REMOVE="$(sed 's/.*] \(.*\):.*/\1/' <<< "$REVERT_INSTALLS")"
for PACKAGE in $REVERT_DO_REMOVE ; do
	REVERT_DO_REMOVABLE+="$PACKAGE "
done

#FIXME Assumes the package arch is the same as the repo arch (i.e. fails for packages with arch "all")
REVERT_DO_DOWNGRADE="$(sed 's/.*] \(.*\):\(.*\) \(.*\) ->.*/\1_\3_\2.deb/' <<< "$REVERT_UPGRADES" | sed 's/:/%3a/')"
for FILE in $REVERT_DO_DOWNGRADE ; do
	if [ ! -f "${FILE}" ] ; then
        FILE_PATH="/var/cache/apt/archives/${FILE}"
		if [ ! -f "$FILE_PATH" ] ; then
            if [ $NO_REPO == 0 ] && apt-get download $(sed 's/\([^_]*\)_\([^_]*\).*/\1=\2/' <<< "$FILE" | sed 's/%3a/:/') ; then
                echo "Downloaded  ok: $FILE"
            else
                echo "File not found: $FILE"
                MISSING_FILES+=$'\n'" $FILE"
            fi
		else
			echo "In  apt  cache: $FILE"
			cp "$FILE_PATH" "."
		fi
	else
		echo "In package dir: $FILE"
	fi
	REVERT_DO_DOWNGRADEABLE+="$FILE "
done

if [ ! -z "${MISING_FILES-unset}" ] ; then
	echo -e "\n\nTo do a full revert you'll need to add these files manually to ${WORKDIR}/packages:"
	echo "$MISSING_FILES"
fi

cd "$WORKDIR"

echo "#!/bin/sh

cd packages

# Remove packages which were installed
dpkg -r --force-depends $REVERT_DO_REMOVABLE

# Install packages which were removed
dpkg -i $REVERT_DO_INSTALLABLE

# Downgrade packages which were upgraded
dpkg -i $REVERT_DO_DOWNGRADEABLE

# Resolve any broken dependencies
aptitude install -f" > revert.sh
chmod 755 revert.sh
