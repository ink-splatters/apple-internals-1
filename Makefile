MY_INTERNALS = $(HOME)/Library/Mobile\ Documents/com~apple~TextEdit/Documents/Apple\ Internals.rtf
DB := $(if $(DB),$(DB:.lz=),internals-$(shell sw_vers -productVersion).db)
DB_TARGETS = db_files
CHECK_TARGETS = check_files

.PHONY: all check $(DB_TARGETS) $(CHECK_TARGETS)
.INTERMEDIATE: $(DB)

all: $(DB).lz check

ifneq ($(wildcard $(MY_INTERNALS)),)
internals.txt: $(MY_INTERNALS)
	textutil -cat txt "$<" -output $@
endif

ifneq ($(wildcard $(DB).lz),)
$(DB): $(DB).lz
	compression_tool -decode -i $< -o $@
else
$(DB):
	@$(MAKE) --silent --jobs=1 $(DB_TARGETS) | sqlite3 -bail $@

$(DB).lz: $(DB)
	compression_tool -encode -i $< -o $@
	tmutil addexclusion $@
endif

check: internals.txt
	@LANG=en sort --ignore-case $< | diff -uw $< -
	@$(MAKE) --silent --jobs=1 $(CHECK_TARGETS)


# MARK: - data extraction helpers

prefix = $$(case $(1) in \
	(macOS) ;; \
	(iOS) echo /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	(tvOS) echo /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/tvOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	(watchOS) echo /Applications/Xcode.app/Contents/Developer/Platforms/WatchOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/watchOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	esac)

find = \
	{ \
		$(2) find /Library /System /bin /dev /private /sbin /usr ! \( -path /System/Volumes/Data -prune \) $(1) 2> /dev/null | sed 's/^/macOS /' ; \
		cd $(call prefix,iOS) ; find . $(1) | sed '1d;s/^\./iOS /' ; \
		cd $(call prefix,tvOS) ; find . $(1) | sed '1d;s/^\./tvOS /' ; \
		cd $(call prefix,watchOS) ; find . $(1) | sed '1d;s/^\./watchOS /' ; \
	}


# MARK: - generator targets for database

$(DB_TARGETS)::
	echo 'BEGIN IMMEDIATE TRANSACTION;'

db_files::
	if ! csrutil status | grep -Fq disabled ; then \
		printf '\033[1mdisable SIP to get complete file information\033[m\n' >&2 ; \
		echo 'FAIL;' ; \
		exit 1 ; \
	fi
	printf '\033[1mcollecting file information...\033[m\n' >&2
	echo 'DROP TABLE IF EXISTS files;'
	echo 'CREATE TABLE files (id INTEGER PRIMARY KEY, os TEXT, path TEXT, executable BOOLEAN);'
	$(call find,,sudo) | sed -E "s/'/''/g;s/([^ ]*) (.*)/INSERT INTO files (os, path) VALUES('\1', '\2');/"
	find $(HOME)/Library | sed "s|^$(HOME)|~|;s/'/''/g;s/.*/INSERT INTO files (os, path) VALUES('macOS', '&');/"
	echo 'CREATE INDEX files_path ON files (path);'

$(DB_TARGETS)::
	echo 'COMMIT TRANSACTION;'


# MARK: - check targets for internals.txt

check_files: internals.txt $(DB)
	printf '\033[1mchecking files...\033[m\n' >&2
	grep -ow '~\?/[^,;]*' $< | sed -E 's/ \(.*\)$$//;s/^\/(etc|var)\//\/private&/' | \
		sed "s/'/''/g;s|.*|SELECT count(*), '&' FROM files WHERE path GLOB '&';|" | \
		sqlite3 $(DB) | sed -n "/^0|/{s/^0|//;p;}"
